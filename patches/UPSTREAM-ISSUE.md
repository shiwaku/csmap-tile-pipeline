# 本家 MIERUNE/csmap-py への issue 下書き（予備）

> **通常は使わない。** 本家は2025-01-07を最後に更新が止まっており、
> 外部からの issue #14 も約10か月未回答のため、issue で方針を仰いでも反応が期待できない。
> **修正が完成済みなので [UPSTREAM-PR.md](UPSTREAM-PR.md) の PR を直接出す方針。**
> PR 本文が症状の説明を兼ねている。
>
> 本ファイルは「PRを出す前に議論したくなった場合」の予備として残す。

投稿先: https://github.com/MIERUNE/csmap-py/issues/new

---

## Title

```
NoData を含む DEM で、データの無い範囲が透明にならない
```

## Body

```markdown
## 症状

NoData が設定された DEM を入力すると、データの無い範囲（海・範囲外・欠測域）が
透明にならず地形として描画されます。地図タイルとして配信すると下のレイヤが隠れてしまいます。

![NoData comparison](https://raw.githubusercontent.com/shiwaku/csmap-tile-pipeline/main/docs/images/nodata-comparison.png)

左: v0.1.4 現状 / 右: 後述の修正後（市松模様が透明部分）。入力DEM・パラメータは同一です。

## 再現

`NoData Value=1.70141e+38` が宣言された DEM（全画素の29.8%がNoData）を入力:

```bash
python -m csmap dem.tif csmap.tif --chunk_size 1024 --gf_size 12 --gf_sigma 3
```

```python
ds = gdal.Open("csmap.tif")
print((ds.GetRasterBand(4).ReadAsArray() == 0).mean() * 100)
# v0.1.4:  0.0%   ← 透明画素がほぼ無い
# 修正後: 29.6%   ← 入力のNoData割合とほぼ一致
```

## 原因

`process.py` の DEM 読み込みが NoData 宣言を参照していないため、
NoData の値がそのまま標高として計算に入ります。

```python
chunk = dem.read(1, window=Window(x, y, chunk_size, chunk_size))
```

`np.isnan(1.70141e+38)` は `False` なので、後段で位置を特定することもできません。
副次的に `calc.slope()` の `p * p` が float32 の上限を超えて
`RuntimeWarning: overflow encountered in multiply` が出ます。

## 修正案

手元では以下の2点で意図どおりになりました（v0.1.4 に対する差分）。

1. **`process.py`** — `dem.read(..., masked=True).filled(np.nan)` で NoData を NaN として読む（単一/並列の2箇所）
2. **`process.py` `_process_chunk`** — NaN の位置のアルファを 0 にする

```python
out_h, out_w = csmap_chunk_margin_removed.shape[1:]
off_y = (chunk.shape[0] - out_h) // 2
off_x = (chunk.shape[1] - out_w) // 2
nodata_mask = np.isnan(chunk)[off_y : off_y + out_h, off_x : off_x + out_w]
csmap_chunk_margin_removed[3, nodata_mask] = 0
```

1 が無いと 2 は空振りします。適用可能なパッチと検証手順は
[こちら](https://github.com/shiwaku/csmap-tile-pipeline/tree/main/patches)に置いています。

## 相談したい点

- `masked=True` はメモリ・速度にオーバーヘッドがあります。常時有効かオプションか
- NoData 宣言の無い DEM では、この修正でも透明化されません。仕様として明記するか

方針が決まれば PR を出します。

## 環境

csmap-py 0.1.4 (PyPI) / Python 3.12 / DEM: GeoTIFF Float32 0.25m `NoData=1.70141e+38`
```

---

## 投稿時のメモ

- 比較画像は本リポジトリの raw URL を参照しているので、そのまま貼れば表示される
- 反応を見てから PR を出す想定。下書きは [UPSTREAM-PR.md](UPSTREAM-PR.md)
- float32 オーバーフロー対策（`calc.py`）は本文では触れず、PR時に含めるか判断する
