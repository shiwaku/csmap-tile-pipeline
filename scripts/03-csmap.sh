#!/bin/bash
# ③ DEM から CS立体図を生成する (csmap-py)
# 使い方: bash 03-csmap.sh <入力DEM.tif> <出力csmap.tif> [csmap-pyのパス]
#
# 事前準備:
#   conda create --name csmap python=3.10 && conda activate csmap
#   pip install poetry && cd csmap-py && poetry install && poetry run pip install -e .
set -eu
IN="${1:?入力DEM.tif を指定してください}"
OUT="${2:?出力csmap.tif を指定してください}"
CSMAP_DIR="${3:-csmap-py}"

# CS立体図のパラメータ（東京都島しょ部・各県で使用している設定）
CHUNK=1024; GF_SIZE=12; GF_SIGMA=3; CURV_SIZE=1
HEIGHT_SCALE="0 1000"; SLOPE_SCALE="0 0.6"; CURV_SCALE="-0.005 0.005"
MAX_WORKERS=1        # 増やすとメモリ使用量も比例して増える

mkdir -p "$(dirname "$OUT")"
cd "$CSMAP_DIR"
poetry run python -m csmap "$OLDPWD/$IN" "$OLDPWD/$OUT" \
  --chunk_size "$CHUNK" \
  --gf_size "$GF_SIZE" --gf_sigma "$GF_SIGMA" \
  --curvature_size "$CURV_SIZE" \
  --height_scale $HEIGHT_SCALE \
  --slope_scale $SLOPE_SCALE \
  --curvature_scale $CURV_SCALE \
  --max_workers "$MAX_WORKERS"
cd "$OLDPWD"
echo "生成: $OUT ($(du -h "$OUT" | cut -f1))"
