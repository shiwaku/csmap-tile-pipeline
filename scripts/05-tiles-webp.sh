#!/bin/bash
# ⑤ CS立体図(EPSG:3857) から WebP ラスタータイルを生成する
# 使い方: bash 05-tiles-webp.sh <入力csmap-3857.tif> <出力ディレクトリ> [品質] [ズーム] [並列数]
set -eu
IN="${1:?入力csmap-3857.tif を指定してください}"
OUT="${2:?出力ディレクトリを指定してください}"
Q="${3:-95}"          # WebP品質。95を採用（docs/webp.md 参照）
ZOOM="${4:-4-19}"
PROC="${5:-6}"

[ -d "$OUT" ] && { echo "既に存在します（スキップ）: $OUT"; exit 0; }

# --xyz を付けないとTMS方式になり、地図ライブラリで上下が反転する
gdal2tiles.py "$IN" "$OUT" \
  -z "$ZOOM" --xyz --processes="$PROC" \
  --tiledriver=WEBP --webp-quality="$Q"

echo "生成: $OUT  $(find "$OUT" -name '*.webp' | wc -l)枚 / $(du -sh "$OUT" | cut -f1)"
