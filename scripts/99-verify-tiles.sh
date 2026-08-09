#!/bin/bash
# ⑥ 生成したWebPタイルを検証する
# 使い方: bash 99-verify-tiles.sh <タイルディレクトリ> [期待枚数]
set -u
DIR="${1:?タイルディレクトリを指定してください}"
EXPECT="${2:-}"
[ -d "$DIR" ] || { echo "ディレクトリがありません: $DIR" >&2; exit 1; }

N=$(find "$DIR" -name '*.webp' -type f | wc -l)
echo "枚数: $N"
[ -n "$EXPECT" ] && { [ "$N" -eq "$EXPECT" ] && echo "  ✅ 期待枚数($EXPECT)と一致" || echo "  ⚠ 期待枚数($EXPECT)と不一致"; }

echo "サイズ0のファイル: $(find "$DIR" -name '*.webp' -type f -size 0 | wc -l) 件"

# WebPのマジックナンバー検査（先頭RIFF + 9〜12バイト目WEBP）
echo -n "形式チェック(全件): "
BAD=$(find "$DIR" -name '*.webp' -type f -print0 \
  | xargs -0 -P 4 -I{} sh -c '
      h=$(dd if="$1" bs=1 count=4 2>/dev/null); w=$(dd if="$1" bs=1 skip=8 count=4 2>/dev/null)
      [ "$h" = RIFF ] && [ "$w" = WEBP ] || echo "$1"' _ {} | wc -l)
[ "$BAD" -eq 0 ] && echo "✅ 全て正常なWebP" || echo "⚠ 不正なファイル ${BAD}件"

echo
echo "ズームレベル別:"
for z in $(ls "$DIR" 2>/dev/null | grep -E '^[0-9]+$' | sort -n); do
  printf "  z%-3s %9d枚 %8s\n" "$z" "$(find "$DIR/$z" -name '*.webp' | wc -l)" "$(du -sh "$DIR/$z" | cut -f1)"
done
echo "合計: $(du -sh "$DIR" | cut -f1)"
