# パイプライン詳細

大量の DEM から CS立体図の WebP タイルを作るまでの全手順。
実例として東京都島しょ部（tokyopc-shima-2023）の実測値を併記する。

---

## 全体像

```
①  DEM (GeoTIFF 多数)          3,254ファイル / 21GB（6島分）
        │  gdalbuildvrt
②  VRT (仮想ラスタ)             島ごとに1ファイル
        │  gdal_translate
③  統合DEM (GeoTIFF)           2.0GB（shima-01の場合）
        │  csmap-py
④  CS立体図 (RGB GeoTIFF)      2.6GB
        │  gdalwarp -t_srs EPSG:3857
⑤  CS立体図 (EPSG:3857)        2.0GB
        │  gdal2tiles.py --tiledriver=WEBP
⑥  WebPタイル                  46,122枚
```

DEM は島・県などの単位でフォルダに分けておき、**単位ごとに①〜⑥を通す**。

---

## ① DEM の配置

配信単位ごとにフォルダを分ける。

```
work/tokyo-shima-2023/dem/
  01/   893ファイル 6.0GB   伊豆大島
  02/   716ファイル 4.2GB   利島・鵜渡根島
  03/   572ファイル 3.8GB   三宅島
  04/   226ファイル 1.5GB   御蔵島
  05/   768ファイル 5.0GB   八丈島・八丈小島
  06/    79ファイル 478MB   青ヶ島
```

サブフォルダに入っていても構わない（`01-build-vrt.sh` は再帰的に探索する）。

---

## ② DEM → VRT

大量の GeoTIFF を **VRT（仮想ラスタ）** として1つに束ねる。
実体をコピーしないため一瞬で終わり、ディスクも消費しない。

```bash
bash scripts/01-build-vrt.sh <DEMディレクトリ> <出力.vrt>
```

内部で実行しているコマンド:

```bash
find <DEMディレクトリ> -name '*.tif' > filelist.txt
gdalbuildvrt -input_file_list filelist.txt <出力.vrt>
```

> ファイル数が多いとコマンドライン長の上限に引っかかるため、
> ワイルドカードではなく **`-input_file_list` を使う**こと。

---

## ③ VRT → 統合DEM GeoTIFF

VRT のままでも次工程に渡せるが、実体化しておくと後段が安定して速い。

```bash
bash scripts/02-vrt-to-tif.sh <入力.vrt> <出力.tif>
```

```bash
gdal_translate -of GTiff \
  -co BIGTIFF=YES -co COMPRESS=DEFLATE -co PREDICTOR=2 -co ZLEVEL=9 -co TILED=YES \
  <入力.vrt> <出力.tif>
```

| オプション | 意味 |
|---|---|
| `BIGTIFF=YES` | 4GB超のTIFFを扱う。DEMは容易に超えるため必須 |
| `COMPRESS=DEFLATE` | 可逆圧縮 |
| `PREDICTOR=2` | 水平差分予測。標高のような連続値によく効く |
| `ZLEVEL=9` | 圧縮率最大 |
| `TILED=YES` | タイル化。部分読み出しが速くなる |

---

## ④ DEM → CS立体図

[csmap-py](https://github.com/MIERUNE/csmap-py) で標高から CS立体図（曲率・傾斜・標高を合成したRGB）を生成する。

> **⚠ 本家の csmap-py は NoData を透明化しない。**
> `patches/csmap-py-nodata.patch` を適用したものを使うこと。
> 適用しないと海や範囲外が不透明に塗り潰される。→ [nodata.md](nodata.md)
>
> ```bash
> python3 -m venv csmapenv
> ./csmapenv/bin/pip install csmap-py==0.1.4
> (cd csmapenv/lib/python3*/site-packages && patch -p1 < ../../../../patches/csmap-py-nodata.patch)
> export CSMAP_CMD="$PWD/csmapenv/bin/python -m csmap"
> ```
>
> 前提として **元DEM に NoData の宣言が必要**（`gdalinfo | grep NoData` で確認）。

```bash
bash scripts/03-csmap.sh <入力DEM.tif> <出力csmap.tif>
```

```bash
poetry run python -m csmap <入力DEM.tif> <出力csmap.tif> \
  --chunk_size 1024 \
  --gf_size 12 --gf_sigma 3 \
  --curvature_size 1 \
  --height_scale 0 1000 \
  --slope_scale 0 0.6 \
  --curvature_scale -0.005 0.005 \
  --max_workers 1
```

パラメータの意味と調整指針は **[parameters.md](parameters.md)** を参照。

> `--max_workers` を増やすと速くなるが、メモリ使用量も比例して増える。
> 大きなDEMでは 1 のままにしておくのが無難。

---

## ⑤ EPSG:3857 に変換

Webメルカトルに投影変換する。タイル生成時の再投影を避けられるため、先に済ませておく。

```bash
bash scripts/04-warp-3857.sh <入力csmap.tif> <出力csmap-3857.tif>
```

```bash
gdalwarp -t_srs EPSG:3857 \
  -co BIGTIFF=YES -co COMPRESS=DEFLATE -co PREDICTOR=2 -co ZLEVEL=9 -co TILED=YES \
  <入力csmap.tif> <出力csmap-3857.tif>
```

---

## ⑥ WebPタイルの生成

```bash
bash scripts/05-tiles-webp.sh <入力csmap-3857.tif> <出力タイルディレクトリ> [品質]
```

```bash
gdal2tiles.py <入力csmap-3857.tif> <出力ディレクトリ> \
  -z 4-19 --xyz --processes=6 \
  --tiledriver=WEBP --webp-quality=95
```

| オプション | 意味 |
|---|---|
| `-z 4-19` | 生成するズームレベル |
| `--xyz` | XYZ方式（Y軸が上から下）。省略するとTMS方式になり地図ライブラリで上下が反転する |
| `--processes=6` | 並列数 |
| `--tiledriver=WEBP` | WebPで出力（GDAL 3.6以降） |
| `--webp-quality=95` | 品質。95を採用（[webp.md](webp.md) 参照） |

### 実測値（青ヶ島 / shima-06）

| 項目 | 値 |
|---|---|
| 入力 | 214.5MB（EPSG:3857 CS立体図） |
| 出力 | 3,456枚 / 66MB |
| 所要時間 | 38秒（`--processes=6`） |
| PNG版との比較 | 296MB → 66MB（**−78%**） |

---

## ⑦ 検証

```bash
bash scripts/99-verify-tiles.sh <タイルディレクトリ>
```

確認する内容:

- 枚数（既存のPNG版がある場合は突き合わせる）
- 全ファイルが正しい WebP か（先頭が `RIFF`、9〜12バイト目が `WEBP`）
- サイズ0のファイルが無いか
- ズームレベルごとの枚数と容量

---

## ⑧ 配信サーバへの反映

タイルの設置と `.htaccess` の設定は **[webp.md](webp.md)** を参照。

**`.htaccess` を先に置くこと。** PNGを削除してから設置すると、その間タイルが404になる。

---

## つまずきやすい点

| 症状 | 原因と対処 |
|---|---|
| 地図の上下が反転する | `--xyz` の付け忘れ（TMS方式で出力されている） |
| `gdalbuildvrt` がエラーになる | ファイル数が多すぎる。`-input_file_list` を使う |
| 4GB超で書き込みに失敗 | `-co BIGTIFF=YES` の付け忘れ |
| `--tiledriver` が無いと言われる | GDAL が 3.6 未満。バージョンを確認する |
| csmap-py がメモリ不足で落ちる | `--max_workers` を減らす。`--chunk_size` を小さくする |
| **海や範囲外が不透明に塗り潰される** | **csmap-py にパッチが未適用、または元DEMにNoData宣言が無い。[nodata.md](nodata.md) 参照** |
| 傾斜が真っ白／おかしい | NoDataの巨大値がfloat32でオーバーフローしている。パッチ③を確認 |
| タイルの継ぎ目に線が出る | DEM間に隙間がある。VRTの元ファイルの網羅性を確認する |

---

# 系統B: 配布済みCS立体図を統合する場合

静岡県・大阪府のように、**自治体がCS立体図そのものを配布している**場合は
csmap-py を使わず、配布データを統合してタイル化する。

```
①  配布ZIP群                   静岡: 310GB相当
        │  7-Zip で展開 → gdal_translate で再圧縮
②  個別GeoTIFF                 tif/ に集約
        │  gdal_merge.py
③  統合CS立体図                静岡 58.5GB / 大阪 12.3GB
        │  gdalwarp -t_srs EPSG:3857
④  CS立体図 (EPSG:3857)        静岡 61.4GB / 大阪 6.8GB
        │  gdal2tiles.py --tiledriver=WEBP
⑤  WebPタイル
```

## ①→② ZIP展開と再圧縮

配布ZIPを展開し、圧縮オプションを揃えて保存し直す。展開した元ファイルは都度削除して
ディスクを節約する。

```bash
7z x <配布.zip> -o<一時ディレクトリ> -aoa
gdal_translate -co COMPRESS=DEFLATE -co PREDICTOR=2 -co ZLEVEL=9 -co TILED=YES \
  <一時ディレクトリ>/xxx.tif tif/xxx.tif
```

## ②→③ 統合

```bash
find tif -name '*.tif' > filelist.txt
gdal_merge.py -o <統合.tif> --optfile filelist.txt
```

> 系統Aの `gdalbuildvrt` と違い、`gdal_merge.py` は実体を作るため時間とディスクを要する。
> 枚数が多い場合は VRT 経由（`gdalbuildvrt` → `gdal_translate`）の方が速い。

## ③→④ 投影変換

系統Aの④と同じ。

## ④→⑤ タイル生成

系統Aの⑥と同じ。大阪では負荷分散のためズームを分割して実行していた。

```bash
gdal2tiles.py osaka-cs_epsg3857.tif osaka-cs-tiles -z 9-18 --xyz --processes=8 --tiledriver=WEBP --webp-quality=95
gdal2tiles.py osaka-cs_epsg3857.tif osaka-cs-tiles -z 4-8  --xyz --processes=8 --tiledriver=WEBP --webp-quality=95
```
