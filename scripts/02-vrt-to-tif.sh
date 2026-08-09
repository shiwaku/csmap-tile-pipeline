#!/bin/bash
# ② VRT を単一の GeoTIFF に実体化する
# 使い方: bash 02-vrt-to-tif.sh <入力.vrt> <出力.tif>
set -eu
IN="${1:?入力.vrt を指定してください}"
OUT="${2:?出力.tif を指定してください}"
mkdir -p "$(dirname "$OUT")"

gdal_translate -of GTiff \
  -co BIGTIFF=YES -co COMPRESS=DEFLATE -co PREDICTOR=2 -co ZLEVEL=9 -co TILED=YES \
  "$IN" "$OUT"
echo "生成: $OUT ($(du -h "$OUT" | cut -f1))"
