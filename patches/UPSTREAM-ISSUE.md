# 本家 MIERUNE/csmap-py への issue 下書き

投稿先: https://github.com/MIERUNE/csmap-py/issues/new

---

## Title

```
NoData を含む DEM を入力すると、データの無い範囲が不透明に描画される
```

## Body

```markdown
## 概要

NoData が設定された DEM を入力すると、**データの無い範囲（海・範囲外・欠測域）が
透明にならず、地形として描画されます。**

生成物を地図タイルとして配信する場合、下のレイヤが隠れてしまうため実用上の問題になります。

![NoData comparison](https://raw.githubusercontent.com/shiwaku/csmap-tile-pipeline/main/docs/images/nodata-comparison.png)

左: v0.1.4 現状の出力（海が塗り潰されている） / 右: 後述の修正を当てた出力（市松模様が透明部分）
入力DEM・パラメータは同一で、csmap-py のコードだけが異なります。

## 再現手順

NoData が宣言された DEM を用意して実行するだけで再現します。

```bash
gdalinfo dem.tif | grep NoData
#   NoData Value=1.70141e+38

python -m csmap dem.tif csmap.tif \
  --chunk_size 1024 --gf_size 12 --gf_sigma 3 --curvature_size 1 \
  --height_scale 0 1000 --slope_scale 0 0.6 --curvature_scale -0.005 0.005
```

出力のアルファチャンネルを確認すると、透明画素がほぼ存在しません。

```python
from osgeo import gdal
ds = gdal.Open("csmap.tif")
a = ds.GetRasterBand(4).ReadAsArray()
print((a == 0).mean() * 100)   # → 0.0
```

### 実測値

東京都の点群由来 DEM（0.25m / Float32 / `NoData=1.70141e+38`、
全画素の 29.8% が NoData）を入力した場合:

| | 出力の透明率 |
|---|---|
| v0.1.4（現状） | **0.0%** |
| 後述の修正を適用 | **29.6%** |

入力 DEM の NoData 画素の割合（29.8%）とほぼ一致します。

## 原因

`csmap/process.py` の DEM 読み込みが NoData 宣言を参照していないため、
NoData の値（この例では `1.70141e+38`）が**標高の実測値として**計算に入ります。

```python
# csmap/process.py
chunk = dem.read(1, window=Window(x, y, chunk_size, chunk_size))
```

また `np.isnan(1.70141e+38)` は `False` であるため、
後段で NoData の位置を特定してアルファに反映することもできません。

副次的な影響として、`calc.slope()` の `p * p` が float32 の上限（約3.4e38）を超えて
`inf` になり、`RuntimeWarning: overflow encountered in multiply` が発生します。

## 修正案

手元では以下の変更で意図どおりの出力になりました。v0.1.4 に対する差分です。

### 1. NoData を NaN として読み込む（`process.py` / 2箇所）

```diff
-                        chunk = dem.read(1, window=Window(x, y, chunk_size, chunk_size))
+                        chunk = dem.read(
+                            1,
+                            window=Window(x, y, chunk_size, chunk_size),
+                            masked=True,
+                        ).filled(np.nan)
```

並列処理側（`ThreadPoolExecutor` を使う分岐）にも同じ変更が必要です。

### 2. NaN の位置のアルファを 0 にする（`process.py` / `_process_chunk`）

```diff
     ]  # shape = (4, chunk_size - margin, chunk_size - margin)
 
+    out_h, out_w = csmap_chunk_margin_removed.shape[1:]
+    off_y = (chunk.shape[0] - out_h) // 2
+    off_x = (chunk.shape[1] - out_w) // 2
+    nodata_mask = np.isnan(chunk)[off_y : off_y + out_h, off_x : off_x + out_w]
+    csmap_chunk_margin_removed[3, nodata_mask] = 0
+
     if lock is None:
```

削られる縁の幅は、入力 `chunk` と出力の形状差から求めています。
パディングやフィルタサイズの実装が変わっても追従します。

1 が無いと 2 は空振りします（NaN が発生しないため）。**2つで1組**です。

### 3. （任意）float32 のオーバーフロー回避（`calc.py`）

```diff
-    p = (z6 - z4) / 2
-    q = (z8 - z2) / 2
+    p = ((z6 - z4) / 2).astype(np.float64)
+    q = ((z8 - z2) / 2).astype(np.float64)
```

1 を適用すれば直接の実害は減りますが、NoData 宣言の無い DEM を扱う際の保険として。

## 相談したい点

修正方針はお任せしたく、以下が気になっています。

- **`masked=True` はメモリ・速度にオーバーヘッドがあります。**
  常時有効にするか、オプション（`--nodata-transparent` 等）にするか
- **2 のマスク位置の求め方。**
  形状差から導出しているので `csmap()` の実装変更には追従しますが、
  縁が上下左右で非対称に削られる実装になった場合は破綻します
- **NoData 宣言の無い DEM では、この修正でも透明化されません。**
  仕様として明記するか、`--src-nodata` のような指定を設けるか

## 環境

- csmap-py: 0.1.4（PyPI）
- Python: 3.12
- rasterio / numpy: 最新
- 入力 DEM: GeoTIFF / Float32 / 0.25m / `NoData Value=1.70141e+38`

## 補足

CS立体図のラスタータイルを作る一連の手順を以下にまとめており、
本件の調査経緯と検証結果もそこに記録しています。

https://github.com/shiwaku/csmap-tile-pipeline
```

---

## 投稿時のメモ

- 比較画像は本リポジトリの raw URL を参照しているので、そのまま貼れば表示される
- issue で反応を見てから PR を出す想定。PR にする場合は修正案 1・2 に絞る
- PR の下書きは [UPSTREAM-PR.md](UPSTREAM-PR.md)
