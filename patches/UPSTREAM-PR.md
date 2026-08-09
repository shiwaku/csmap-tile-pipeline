# 本家 MIERUNE/csmap-py への PR 下書き

issue は立てず、PR 単体で完結する構成にしている（本文冒頭で症状から説明する）。

fork とブランチは作成済み。コード修正・テストともコミット・push 済み。

- https://github.com/shiwaku/csmap-py  ブランチ `fix/nodata-transparency`
- ローカル: `C:\Users\yshiw\Documents\GIS\csmap-py-fork`

## 投稿コマンド

```bash
cd /mnt/c/Users/yshiw/Documents/GIS/csmap-py-fork
gh pr create --repo MIERUNE/csmap-py --base main \
  --head shiwaku:fix/nodata-transparency \
  --title "fix: NoData の範囲を透明にする"
```

内容を修正する場合はローカルで編集して `git push` すれば PR に反映される。

---

## Title

```
fix: NoData の範囲を透明にする
```

## Body

```markdown
## 症状

NoData が設定された DEM を入力すると、データの無い範囲（海・範囲外・欠測域）が
透明にならず地形として描画されます。地図タイルとして配信すると下のレイヤが隠れてしまいます。

![NoData comparison](https://raw.githubusercontent.com/shiwaku/csmap-tile-pipeline/main/docs/images/nodata-comparison.png)

左: 修正前 / 右: 修正後（市松模様が透明部分）。入力DEM・パラメータは同一です。

## 原因

DEM の読み込みが NoData 宣言を参照していないため、NoData の値
（この例では `1.70141e+38`）が標高の実測値として計算に入っていました。

```python
chunk = dem.read(1, window=Window(x, y, chunk_size, chunk_size))
```

`np.isnan(1.70141e+38)` は `False` なので、後段で位置を特定することもできません。

## 変更内容

`csmap/process.py` のみ、26行です。

**1. `_read_chunk()` を追加し、NoData を NaN として読む**

```python
chunk = dem.read(1, window=window, masked=True)
if not np.issubdtype(chunk.dtype, np.floating):
    chunk = chunk.astype("float32")
return chunk.filled(np.nan)
```

整数型の DEM は NaN を保持できないため float32 に昇格させています。
これが無いと `TypeError: Cannot convert fill_value nan to dtype int16` になります
（SRTM や ASTER GDEM は Int16 です）。float64 の DEM は精度を落とさずそのまま扱います。

**2. `_process_chunk()` で NaN の位置のアルファを 0 にする**

```python
out_h, out_w = csmap_chunk_margin_removed.shape[1:]
off_y = (chunk.shape[0] - out_h) // 2
off_x = (chunk.shape[1] - out_w) // 2
nodata_mask = np.isnan(chunk)[off_y : off_y + out_h, off_x : off_x + out_w]
csmap_chunk_margin_removed[3, nodata_mask] = 0
```

削られる縁の幅は入力 `chunk` と出力の形状差から求めているので、
パディングやフィルタサイズの実装が変わっても追従します。

## テスト

`tests/test_nodata.py` を追加しました。フィクスチャは増やさず、テスト内で合成DEMを生成します。

| テスト | 内容 |
|---|---|
| `test_nodata_is_transparent` | dtype/NoData値の6通り（float32の−9999/NaN/1.70141e+38、int16/int32/uint16）で、透明画素の割合が入力のNoData比率と一致すること |
| `test_nodata_transparent_by_worker` | 並列処理でも結果が一致すること |
| `test_no_nodata_declared_stays_opaque` | NoData宣言の無いDEMでは全て不透明のままであること |

```
修正前(v0.1.4): 6 failed, 2 passed
修正後:         8 passed（既存3件と合わせて 11 passed）
```

既存の3件も通ります。

## 実データでの確認

東京都の点群由来 DEM（0.25m / Float32 / `NoData=1.70141e+38`、
全画素の 29.8% が NoData / 11,203 x 14,780）:

| | 出力の透明率 |
|---|---|
| v0.1.4 | 0.00% |
| 本PR | **29.63%** |

入力の NoData 比率とほぼ一致します。

性能（float32 1200x1200 / chunk 1024）:

| | 所要 | 最大メモリ |
|---|---|---|
| v0.1.4 | 0.99秒 | 220.6MB |
| 本PR | 0.66秒 | 226.0MB (+2.5%) |

`masked=True` のオーバーヘッドを懸念していましたが、実測では問題ありませんでした。

## 既存挙動への影響

**NoData が宣言された DEM では出力が変わります。** これまで不透明だった範囲が透明になります。

- NoData 宣言の無い DEM では出力は変わりません（既存テスト3件が通ることで確認）
- 現状の「NoData も地形として描画される」挙動に依存している利用者がいる場合、影響を受けます

## 質問

NoData 宣言の無い DEM では、この修正でも透明化されません。
`--src-nodata` のような指定を設けるべきか、仕様として README に明記するにとどめるか、
ご判断をうかがえればと思います。必要であれば追加で対応します。

## 補足

CS立体図のラスタータイルを作る一連の手順を以下にまとめており、
本件の調査経緯と検証結果もそこに記録しています。

https://github.com/shiwaku/csmap-tile-pipeline
```

---

## メモ

- 比較画像は csmap-tile-pipeline の raw URL を参照しているため、そのまま貼れば表示される
- 本家は2025-01-07を最後に更新が止まっており、外部からのissue #14 も未回答。
  マージされない可能性は高いが、fork が公開されているため実用上は困らない
- `02-float64-slope.patch`（float32オーバーフロー回避）は本家テストを壊すため本PRには含めない
