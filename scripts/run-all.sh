#!/bin/bash
# datasets.tsv に従って WebPタイルを一括生成する
#
# 使い方:
#   bash run-all.sh                     全件（枚数の小さい順）
#   bash run-all.sh pref-kyoto ...      指定したIDのみ
#   DRY=1 bash run-all.sh               実行計画の確認のみ
#   ORDER=desc bash run-all.sh          枚数の大きい順
#   QUALITY=90 bash run-all.sh          WebP品質を変更（既定95）
#
# 生成済みのディレクトリはスキップするので、中断しても同じコマンドで再開できる。
set -u
cd "$(dirname "$0")/.."
TSV=datasets.tsv
Q="${QUALITY:-95}"
DRY="${DRY:-0}"
ORDER="${ORDER:-asc}"
OUT_ROOT="${OUT_ROOT:-work/tiles}"

LOG_DIR=work/logs
mkdir -p "$LOG_DIR" "$OUT_ROOT"
LOG="$LOG_DIR/run-$(date +%Y%m%d-%H%M%S).log"

win2wsl() { echo "$1" | sed -E 's#^([A-Za-z]):/#/mnt/\l\1/#'; }
say() { echo "$*" | tee -a "$LOG"; }

# id / source / expect / gb を枚数順に並べる
SORT_OPT="-k3,3n"
[ "$ORDER" = "desc" ] && SORT_OPT="-k3,3nr"
ROWS=$(awk -F'\t' 'NR>1 && $1 ~ /^[0-9]+$/ {print $2"\t"$8"\t"$6"\t"$7}' "$TSV" | sort -t$'\t' $SORT_OPT)

TARGETS="$*"
TOTAL=$(echo "$ROWS" | wc -l)
say "=== WebPタイル生成 ==="
say "開始    : $(date '+%Y-%m-%d %H:%M:%S')"
say "品質    : q=$Q"
say "出力先  : $OUT_ROOT"
say "順序    : $([ "$ORDER" = desc ] && echo 大きい順 || echo 小さい順)"
say "ログ    : $LOG"
say ""

i=0; done_n=0; skip_n=0; fail_n=0
START_ALL=$(date +%s)

while IFS=$'\t' read -r id src expect gb; do
  i=$((i+1))
  [ -n "$TARGETS" ] && ! echo " $TARGETS " | grep -q " $id " && continue

  OUT="$OUT_ROOT/$id"
  SRC=$(win2wsl "$src")

  if [ -d "$OUT" ]; then
    n=$(find "$OUT" -name '*.webp' 2>/dev/null | wc -l)
    say "[$i/$TOTAL] $id : スキップ（生成済み ${n}枚）"
    skip_n=$((skip_n+1)); continue
  fi
  if [ ! -f "$SRC" ]; then
    say "[$i/$TOTAL] $id : ⚠ ソースが見つかりません ($SRC)"
    fail_n=$((fail_n+1)); continue
  fi

  say "[$i/$TOTAL] $id : 開始 $(date '+%H:%M:%S')  入力 $(du -h "$SRC" | cut -f1)  期待 ${expect}枚 (現${gb}GB)"
  [ "$DRY" = 1 ] && continue

  t0=$(date +%s)
  if bash scripts/05-tiles-webp.sh "$SRC" "$OUT" "$Q" >> "$LOG" 2>&1; then
    t1=$(date +%s); el=$((t1-t0)); [ $el -eq 0 ] && el=1
    n=$(find "$OUT" -name '*.webp' | wc -l)
    sz=$(du -sh "$OUT" | cut -f1)
    ok=$([ "$n" -eq "$expect" ] && echo "✅ 枚数一致" || echo "⚠ 期待${expect}枚と不一致")
    say "         完了 $((el/3600))時間$((el%3600/60))分  ${n}枚 / ${sz}  $((n/el))枚/秒  $ok"
    done_n=$((done_n+1))
  else
    say "         ❌ 失敗（詳細は $LOG）"
    fail_n=$((fail_n+1))
  fi
done <<< "$ROWS"

EL=$(( $(date +%s) - START_ALL ))
say ""
say "=== 終了 $(date '+%Y-%m-%d %H:%M:%S') ==="
say "所要    : $((EL/3600))時間$((EL%3600/60))分"
say "生成    : ${done_n}件 / スキップ ${skip_n}件 / 失敗 ${fail_n}件"
say "合計    : $(find "$OUT_ROOT" -name '*.webp' 2>/dev/null | wc -l)枚 / $(du -sh "$OUT_ROOT" 2>/dev/null | cut -f1)"
