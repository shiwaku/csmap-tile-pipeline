#!/bin/bash
# 生成済みタイルを全件検証し、結果を一覧で出力する
#
# 使い方:
#   OUT_ROOT=~/csmap-tiles bash verify-all.sh
#   OUT_ROOT=~/csmap-tiles bash verify-all.sh > work/logs/verify.txt
#
# 確認する内容:
#   - 枚数（datasets.tsv の期待値と比較。ずれは異常とは限らないので参考値）
#   - 全ファイルが正しい WebP か（RIFF....WEBP のマジックナンバー）
#   - サイズ0のファイルが無いか
#   - NoData が透明化されているか（部分透明タイルの有無）
#   - ズームレベルの範囲と容量
set -u
cd "$(dirname "$0")/.."
OUT_ROOT="${OUT_ROOT:-work/tiles}"
TSV=datasets.tsv

[ -d "$OUT_ROOT" ] || { echo "出力先がありません: $OUT_ROOT" >&2; exit 1; }

printf "%-24s %10s %10s %8s %9s %8s %s\n" \
  "データセット" "生成枚数" "台帳の値" "容量" "透明タイル" "不正" "判定"
printf '%.0s-' {1..92}; echo

total_n=0; total_bad=0; ng=0; ok=0

for d in "$OUT_ROOT"/*/; do
  [ -d "$d" ] || continue
  id=$(basename "$d")

  expect=$(awk -F'\t' -v i="$id" 'NR>1 && $2==i {print $6}' "$TSV")
  expect="${expect:--}"

  n=$(find "$d" -name '*.webp' -type f | wc -l)
  [ "$n" -eq 0 ] && { printf "%-24s %10s %10s %8s %9s %8s %s\n" "$id" 0 "$expect" - - - "⚠ 空"; ng=$((ng+1)); continue; }

  sz=$(du -sh "$d" | cut -f1)
  zero=$(find "$d" -name '*.webp' -type f -size 0 | wc -l)

  # WebPの妥当性（先頭RIFF + 9〜12バイト目WEBP）を全件確認
  bad=$(find "$d" -name '*.webp' -type f -print0 \
    | xargs -0 -P 8 -I{} sh -c '
        h=$(dd if="$1" bs=1 count=4 2>/dev/null); w=$(dd if="$1" bs=1 skip=8 count=4 2>/dev/null)
        [ "$h" = RIFF ] && [ "$w" = WEBP ] || echo x' _ {} | wc -l)
  bad=$((bad + zero))

  # NoDataの透明化を確認する。
  # find の出力順はディレクトリ順＝空間的に隣接するため、先頭から取ると
  # 内陸部に偏って部分透明タイルを見逃す。複数ズームから無作為抽出する。
  partial=$(python3 -c '
import sys, glob, random
from osgeo import gdal
gdal.UseExceptions()
random.seed(0)
d = sys.argv[1]
zs = sorted((int(z.split("/")[-1]) for z in glob.glob(d + "/*") if z.split("/")[-1].isdigit()))
zs = zs[len(zs)//2:]          # 浅すぎるズームは枚数が少ないので中間以降を見る
total = 0
for z in zs[:4]:
    fs = glob.glob(f"{d}/{z}/*/*.webp")
    if not fs: continue
    for f in random.sample(fs, min(150, len(fs))):
        try:
            ds = gdal.Open(f)
            if ds.RasterCount >= 4:
                t = (ds.GetRasterBand(4).ReadAsArray() == 0).mean()
                if 0.01 < t < 0.99:
                    total += 1
            ds = None
        except Exception:
            pass
print(total)' "$d" 2>/dev/null || echo 0)

  if [ "$bad" -gt 0 ]; then v="❌ 不正ファイル"; ng=$((ng+1))
  elif [ "${partial:-0}" -eq 0 ]; then v="⚠ 透明タイル無し"; ng=$((ng+1))
  else v="✅"; ok=$((ok+1)); fi

  printf "%-24s %10d %10s %8s %9s %8d %s\n" "$id" "$n" "$expect" "$sz" "${partial:-0}件" "$bad" "$v"
  total_n=$((total_n+n)); total_bad=$((total_bad+bad))
done

printf '%.0s-' {1..92}; echo
printf "%-24s %10d %10s %8s\n" "合計" "$total_n" "" "$(du -sh "$OUT_ROOT" | cut -f1)"
echo
echo "正常 ${ok}件 / 要確認 ${ng}件 / 不正ファイル ${total_bad}件"
echo
echo "※ 「台帳の値」はサーバ上のPNG枚数。手元のソースが新しい版だと枚数が増えることがある"
echo "※ 「透明タイル」は中間〜最深ズームから各150枚を無作為抽出した中の部分透明タイル数。0件ならNoData透明化を疑う"
