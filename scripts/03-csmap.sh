#!/bin/bash
# ③ DEM から CS立体図を生成する (csmap-py)
# 使い方: bash 03-csmap.sh <入力DEM.tif|.vrt> <出力csmap.tif>
#
# 実行方法は環境変数 CSMAP_CMD で切り替える（既定は python -m csmap）
#   pip でインストールした場合          : CSMAP_CMD="python3 -m csmap"
#   専用venvの場合                      : CSMAP_CMD="/path/to/venv/bin/python -m csmap"
#   csmap-py のリポジトリを使う場合      : CSMAP_CMD="poetry run python -m csmap" かつ
#                                         事前に csmap-py ディレクトリで poetry install
#
# 事前準備（pip の場合）:
#   python3 -m venv csmapenv && ./csmapenv/bin/pip install csmap-py
set -eu
IN="${1:?入力DEM(.tif|.vrt) を指定してください}"
OUT="${2:?出力csmap.tif を指定してください}"

CSMAP_CMD="${CSMAP_CMD:-python3 -m csmap}"

# CS立体図のパラメータ。全データセットで統一している（docs/parameters.md 参照）
CHUNK_SIZE="${CHUNK_SIZE:-1024}"
GF_SIZE="${GF_SIZE:-12}"
GF_SIGMA="${GF_SIGMA:-3}"
CURVATURE_SIZE="${CURVATURE_SIZE:-1}"
HEIGHT_SCALE="${HEIGHT_SCALE:-0 1000}"
SLOPE_SCALE="${SLOPE_SCALE:-0 0.6}"
CURVATURE_SCALE="${CURVATURE_SCALE:--0.005 0.005}"
MAX_WORKERS="${MAX_WORKERS:-1}"    # 増やすとメモリ使用量も比例して増える

mkdir -p "$(dirname "$OUT")"

echo "csmap: $IN → $OUT"
echo "  gf_size=$GF_SIZE gf_sigma=$GF_SIGMA curvature_size=$CURVATURE_SIZE"
echo "  height_scale=[$HEIGHT_SCALE] slope_scale=[$SLOPE_SCALE] curvature_scale=[$CURVATURE_SCALE]"

$CSMAP_CMD "$IN" "$OUT" \
  --chunk_size "$CHUNK_SIZE" \
  --gf_size "$GF_SIZE" --gf_sigma "$GF_SIGMA" \
  --curvature_size "$CURVATURE_SIZE" \
  --height_scale $HEIGHT_SCALE \
  --slope_scale $SLOPE_SCALE \
  --curvature_scale $CURVATURE_SCALE \
  --max_workers "$MAX_WORKERS"

echo "生成: $OUT ($(du -h "$OUT" | cut -f1))"
