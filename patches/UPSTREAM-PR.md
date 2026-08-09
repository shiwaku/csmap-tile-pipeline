# 本家 MIERUNE/csmap-py への PR 下書き

issue（[UPSTREAM-ISSUE.md](UPSTREAM-ISSUE.md)）で反応を見てから出す想定。

---

## 手順

```bash
# 1. fork して clone
gh repo fork MIERUNE/csmap-py --clone --remote
cd csmap-py
git checkout -b fix/nodata-transparency

# 2. パッチを適用
patch -p1 < /path/to/patches/csmap-py-nodata.patch

# 3. 確認
grep -c 'masked=True' csmap/process.py   # 2
grep -c 'nodata_mask' csmap/process.py   # 2
grep -c 'float64'     csmap/calc.py      # 2

# 4. push して PR
git add -A && git commit -m "fix: make NoData areas transparent"
git push -u origin fix/nodata-transparency
gh pr create --repo MIERUNE/csmap-py --fill
```

---

## Title

```
fix: NoData の範囲を透明にする
```

## Body

```markdown
## 概要

NoData が設定された DEM を入力したとき、データの無い範囲（海・範囲外・欠測域）が
不透明に描画される問題を修正します。

関連 issue: #<issue番号>

![NoData comparison](https://raw.githubusercontent.com/shiwaku/csmap-tile-pipeline/main/docs/images/nodata-comparison.png)

左: 修正前 / 右: 修正後（市松模様が透明部分）。入力DEM・パラメータは同一です。

## 変更内容

### 1. `process.py` — NoData を NaN として読み込む（2箇所）

```python
chunk = dem.read(
    1,
    window=Window(x, y, chunk_size, chunk_size),
    masked=True,
).filled(np.nan)
```

現状は NoData 宣言を参照せず生の値を読むため、NoData の値
（例: `1.70141e+38`）が標高の実測値として計算に入っていました。

単一スレッド側と `ThreadPoolExecutor` を使う並列側の両方を変更しています。

### 2. `process.py` — NaN の位置のアルファを 0 にする

```python
out_h, out_w = csmap_chunk_margin_removed.shape[1:]
off_y = (chunk.shape[0] - out_h) // 2
off_x = (chunk.shape[1] - out_w) // 2
nodata_mask = np.isnan(chunk)[off_y : off_y + out_h, off_x : off_x + out_w]
csmap_chunk_margin_removed[3, nodata_mask] = 0
```

削られる縁の幅は入力 `chunk` と出力の形状差から求めているため、
パディングやフィルタサイズの実装が変わっても追従します。

1 が無いと 2 は空振りします（`np.isnan(1.70141e+38)` は `False`）。2つで1組です。

### 3. `calc.py` — float32 のオーバーフローを避ける

```python
p = ((z6 - z4) / 2).astype(np.float64)
q = ((z8 - z2) / 2).astype(np.float64)
```

NoData の巨大値が残っている場合、`p * p` が float32 の上限（約3.4e38）を超えて
`inf` になり `RuntimeWarning: overflow encountered in multiply` が出ます。
1 を入れれば直接の実害は減りますが、NoData 宣言の無い DEM への保険として含めています。
不要であれば外します。

## 検証

東京都の点群由来 DEM（0.25m / Float32 / `NoData=1.70141e+38`、
全画素の 29.8% が NoData / 11,203 x 14,780）で確認しました。

| | 出力の透明率 |
|---|---|
| v0.1.4（現状） | 0.0% |
| 本PR適用後 | **29.6%** |

入力 DEM の NoData 画素の割合とほぼ一致します。

また、別途手元で運用している改造版（同等の修正を独自に当てたもの）の出力と
**画素単位で完全一致**することを確認しました（8,591,616画素を照合し相違0）。

## 影響と注意点

- **`masked=True` はメモリ・速度にオーバーヘッドがあります。**
  常時有効で良いか、オプション化すべきかはご判断ください
- **NoData 宣言の無い DEM では透明化されません。**
  この場合は入力側で `gdal_edit.py -a_nodata` などによる宣言が必要です
- 既存の挙動に依存している利用者がいる場合、出力が変わります
```

---

## 補足

- PR にする場合、変更 3（`calc.py`）は分けても良い。1・2 が本体
- 本家が「オプション化したい」等の方針を示した場合は、それに合わせて書き直す
