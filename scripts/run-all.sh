#!/bin/bash
# datasets.tsv に従って WebPタイルを一括生成する
# 使い方: bash run-all.sh [データセットID ...]     IDを省略すると全件
#         DRY=1 bash run-all.sh                    実行内容の確認のみ
set -u
cd "$(dirname "$0")/.."
TSV=datasets.tsv
Q="${QUALITY:-95}"
DRY="${DRY:-0}"

win2wsl() { echo "$1" | sed -E 's#^([A-Za-z]):/#/mnt/\l\1/#'; }

TARGETS="$*"
awk -F'\t' 'NR>1 && $1 ~ /^[0-9]+$/ {print $2"\t"$8"\t"$5"\t"$6}' "$TSV" | while IFS=$'\t' read -r id src tile_path expect; do
  [ -n "$TARGETS" ] && ! echo " $TARGETS " | grep -q " $id " && continue
  SRC=$(win2wsl "$src")
  OUT="work/tiles/$id"

  if [ ! -f "$SRC" ]; then echo "⚠ $id: ソースが見つかりません ($SRC)"; continue; fi
  if [ -d "$OUT" ]; then echo "・$id: 生成済みのためスキップ"; continue; fi

  echo "=== $id ==="
  echo "  入力: $SRC ($(du -h "$SRC" 2>/dev/null | cut -f1))"
  echo "  出力: $OUT  (期待枚数 $expect)"
  [ "$DRY" = 1 ] && continue

  bash scripts/05-tiles-webp.sh "$SRC" "$OUT" "$Q"
  bash scripts/99-verify-tiles.sh "$OUT" "$expect"
done
