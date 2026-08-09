#!/bin/bash
# ① 大量のDEM GeoTIFF を VRT（仮想ラスタ）に束ねる
# 使い方: bash 01-build-vrt.sh <DEMディレクトリ> <出力.vrt>
set -eu
SRC="${1:?DEMディレクトリを指定してください}"
OUT="${2:?出力.vrt を指定してください}"
[ -d "$SRC" ] || { echo "ディレクトリがありません: $SRC" >&2; exit 1; }
mkdir -p "$(dirname "$OUT")"

LIST="$(mktemp)"; trap 'rm -f "$LIST"' EXIT
find "$SRC" -type f \( -iname '*.tif' -o -iname '*.tiff' \) | sort > "$LIST"
N=$(wc -l < "$LIST")
[ "$N" -eq 0 ] && { echo "GeoTIFFが見つかりません: $SRC" >&2; exit 1; }
echo "対象: ${N}ファイル ($(du -sh "$SRC" | cut -f1))"

# ファイル数が多いとコマンドライン長の上限に達するため -input_file_list を使う
gdalbuildvrt -input_file_list "$LIST" "$OUT"
echo "生成: $OUT"
