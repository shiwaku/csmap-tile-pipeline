# csmap-py へのパッチ

## csmap-py-nodata.patch

**本家の csmap-py は NoData（データの無い範囲）を透明化しない。**
このパッチを当てないと、海・対象外の市町村・LiDARの欠測域が
不透明に塗り潰され、地図に重ねたとき下のレイヤが見えなくなる。

- 対象: [MIERUNE/csmap-py](https://github.com/MIERUNE/csmap-py) **v0.1.4**
- 本家への取り込み: **未（2025-01-07 時点の main で確認）**
- 詳細な解説: [../docs/nodata.md](../docs/nodata.md)

### 変更点（3箇所すべて必要）

| # | ファイル | 内容 |
|---|---|---|
| ① | `process.py` ×2箇所 | `dem.read(..., masked=True).filled(np.nan)` — NoDataをNaNに置き換える |
| ② | `process.py` | `csmap_chunk_margin_removed[3, mask] = 0` — NaNの位置のアルファを0にする |
| ③ | `calc.py` | `p`,`q` を `.astype(np.float64)` — float32のオーバーフロー回避 |

①が無いと②は空振りする（`np.isnan(1.70141e+38)` は `False` のため）。

### 適用方法

```bash
python3 -m venv csmapenv
./csmapenv/bin/pip install csmap-py==0.1.4
cd csmapenv/lib/python3*/site-packages
patch -p1 < /path/to/patches/csmap-py-nodata.patch
```

適用できたか確認:

```bash
grep -c 'masked=True' csmap/process.py    # 2 が返れば①OK
grep -c 'mask\] = 0'  csmap/process.py    # 1 が返れば②OK
grep -c 'float64'     csmap/calc.py       # 2 が返れば③OK
```

### 効果の実測（青ヶ島 / 同一DEM・同一パラメータ）

| csmap-py | 透明率 |
|---|---|
| 本家 0.1.4 素のまま | 0.0% |
| 本家 0.1.4 + このパッチ | **29.6%** |
| 2025年に生成した正解データ | 29.6% |

### 前提

**DEM側に NoData の宣言が必要。** 宣言が無いDEMではパッチを当てても透明化されない。
対処は [../docs/nodata.md](../docs/nodata.md) の「4. DEM に NoData の宣言が必要」を参照。
