# csmap-tiles

大量の DEM（GeoTIFF）から **CS立体図**を作成し、**WebPラスタータイル**として配信するまでの手順とスクリプト。

CS立体図の生成には [MIERUNE/csmap-py](https://github.com/MIERUNE/csmap-py) を使用する。
[林野庁「CS立体図」](https://www.rinya.maff.go.jp/j/seibi/sagyoudo/attach/pdf/romou-12.pdf) に基づく。

## パイプライン

```
①  DEM (GeoTIFF 多数)          例: 3,254ファイル / 21GB
        │  gdalbuildvrt
②  VRT (仮想ラスタ)             1ファイル
        │  gdal_translate
③  統合DEM (GeoTIFF)           例: 2.0GB
        │  csmap-py
④  CS立体図 (RGB GeoTIFF)      例: 2.6GB
        │  gdalwarp -t_srs EPSG:3857
⑤  CS立体図 (EPSG:3857)        例: 2.0GB
        │  gdal2tiles.py --tiledriver=WEBP
⑥  WebPタイル (z/x/y.webp)     例: 46,122枚 / 350MB
```

各段階の詳細は **[docs/pipeline.md](docs/pipeline.md)** を参照。

> ## ⚠ 最初に読むこと
>
> **本家の csmap-py は NoData（データの無い範囲）を透明化しない。**
> `patches/01-nodata-transparency.patch` の適用が必須で、これを怠ると海や範囲外が
> 不透明に塗り潰される。東京都島しょ部は これが原因で作り直している。
> 前提として **DEM側に NoData の宣言が必要**。
> → **[docs/nodata.md](docs/nodata.md)** / **[patches/README.md](patches/README.md)**

## クイックスタート

```bash
# 環境構築（初回のみ）— パッチ適用が必須
python3 -m venv csmapenv
./csmapenv/bin/pip install csmap-py==0.1.4
(cd csmapenv/lib/python3*/site-packages && patch -p1 < ../../../../patches/01-nodata-transparency.patch)
export CSMAP_CMD="$PWD/csmapenv/bin/python -m csmap"

# ①→② 大量DEMをVRTに束ねる
bash scripts/01-build-vrt.sh work/tokyo-shima-2023/dem/01 work/tokyo-shima-2023/shima-01-dem.vrt

# ②→③ VRTを単一GeoTIFFに
bash scripts/02-vrt-to-tif.sh work/tokyo-shima-2023/shima-01-dem.vrt work/tokyo-shima-2023/shima-01-dem.tif

# ③→④ CS立体図を生成
bash scripts/03-csmap.sh work/tokyo-shima-2023/shima-01-dem.tif work/tokyo-shima-2023/shima-01-dem-csmap.tif

# ④→⑤ EPSG:3857 に変換
bash scripts/04-warp-3857.sh work/tokyo-shima-2023/shima-01-dem-csmap.tif work/tokyo-shima-2023/shima-01-dem-csmap-3857.tif

# ⑤→⑥ WebPタイルを生成
bash scripts/05-tiles-webp.sh work/tokyo-shima-2023/shima-01-dem-csmap-3857.tif work/tokyo-shima-2023/tiles/tokyopc-shima-01-2023-cs-tiles

# 検証
bash scripts/99-verify-tiles.sh work/tokyo-shima-2023/tiles/tokyopc-shima-01-2023-cs-tiles
```

データセットをまとめて処理する場合は `datasets.tsv` に定義して `scripts/run-all.sh` を使う。

## なぜ WebP か

PNG から WebP(q=95) に変えることで **容量が約78%減る**。画質は目視で区別がつかない。

| 方式 | 削減率 |
|---|---|
| PNG（現行） | — |
| WebP 可逆 | 33% |
| PNG8 (256色) | 62% |
| **WebP q=95** | **78%** |
| WebP q=90 | 84% |
| WebP q=85 | 88%（微地形テクスチャが劣化するため不採用） |

配信サーバでは `.htaccess` により **`.png` のURLのまま WebP を返せる**ので、
利用側（自作の地図・外部サイト）の修正は不要。詳細は **[docs/webp.md](docs/webp.md)**。

## ディレクトリ構成

```
README.md
datasets.tsv              データセット台帳（元DEM・CS立体図・配信先の対応）
docs/
  pipeline.md             ①〜⑥の詳細手順
  parameters.md           csmap-py のパラメータ解説
  nodata.md               NoData(透明領域)の扱い ← 最も事故が多い
  webp.md                 WebP化と .htaccess による配信
  datasets.md             データセット一覧と現況
patches/
  01-nodata-transparency.patch  本家csmap-pyへの必須パッチ（NoData透明化）
  02-float64-slope.patch        既存データ再現用（任意）
scripts/
  01-build-vrt.sh         大量DEM → VRT
  02-vrt-to-tif.sh        VRT → 統合DEM GeoTIFF
  03-csmap.sh             DEM → CS立体図
  04-warp-3857.sh         → EPSG:3857
  05-tiles-webp.sh        → WebPタイル
  98-check-nodata.sh      NoData(透明領域)が正しいか検証
  99-verify-tiles.sh      タイルの枚数・形式を検証
  run-all.sh              datasets.tsv に従って一括実行
inventory/
  csmap-tif-all.tsv       全ドライブのCS立体図GeoTIFF棚卸し
work/                     作業領域（.gitignore 対象）
```

`work/` 配下の DEM・GeoTIFF・タイル・zip はサイズが大きいため **Gitには含めない**。

## 必要な環境

| ツール | 用途 | 確認済みバージョン |
|---|---|---|
| GDAL | VRT作成・投影変換・タイル生成 | 3.11.4 |
| csmap-py | CS立体図の生成 | 0.1.4 + 独自パッチ |
| Python | csmap-py の実行 | 3.10 |

GDAL は **3.6以降**が必要（`gdal2tiles.py --tiledriver=WEBP` のため）。

```bash
python3 -c "from osgeo import gdal; print(gdal.__version__)"
gdal2tiles.py --help | grep tiledriver
```
