#!/bin/bash
# ④ CS立体図を EPSG:3857 (Webメルカトル) に変換する
# 使い方: bash 04-warp-3857.sh <入力csmap.tif> <出力csmap-3857.tif>
set -eu
IN="${1:?入力csmap.tif を指定してください}"
OUT="${2:?出力csmap-3857.tif を指定してください}"
mkdir -p "$(dirname "$OUT")"

gdalwarp -t_srs EPSG:3857 \
  -co BIGTIFF=YES -co COMPRESS=DEFLATE -co PREDICTOR=2 -co ZLEVEL=9 -co TILED=YES \
  "$IN" "$OUT"
echo "生成: $OUT ($(du -h "$OUT" | cut -f1))"
