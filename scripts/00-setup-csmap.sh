#!/bin/bash
# ⓪ csmap-py（パッチ適用版）の実行環境を作る
#
# 本家の csmap-py は NoData を透明化しないため、パッチの適用が必須。
# → docs/nodata.md / patches/README.md
#
# 使い方: bash 00-setup-csmap.sh [venvのパス]
#         既定は <リポジトリ>/csmapenv
#
# 実行後、表示される export を実行してから 03-csmap.sh を使う。
set -eu
cd "$(dirname "$0")/.."
REPO="$PWD"
VENV="${1:-$REPO/csmapenv}"
VERSION="${CSMAP_VERSION:-0.1.4}"

if [ -d "$VENV" ]; then
  echo "既に存在します: $VENV"
  echo "作り直す場合は先に削除してください: rm -rf \"$VENV\""
else
  echo "=== venv を作成 ==="
  python3 -m venv "$VENV"
  echo "=== csmap-py $VERSION を導入 ==="
  "$VENV/bin/pip" install --quiet --upgrade pip
  "$VENV/bin/pip" install --quiet "csmap-py==$VERSION"
fi

SP=$("$VENV/bin/python" -c "import csmap, os; print(os.path.dirname(os.path.dirname(csmap.__file__)))")

echo "=== パッチを適用 ==="
apply() {
  local patch="$1" label="$2"
  if patch -p1 -d "$SP" --dry-run --silent < "$patch" 2>/dev/null; then
    patch -p1 -d "$SP" --silent < "$patch"
    echo "  ✅ $label"
  elif patch -p1 -d "$SP" --dry-run --reverse --silent < "$patch" 2>/dev/null; then
    echo "  ・$label（適用済み）"
  else
    echo "  ❌ $label の適用に失敗しました" >&2
    return 1
  fi
}
apply "$REPO/patches/01-nodata-transparency.patch" "01-nodata-transparency（必須）"

# 02 は本家テストを壊すが、既存データセットを画素単位で再現するために使う
if [ "${APPLY_FLOAT64:-1}" = "1" ]; then
  apply "$REPO/patches/02-float64-slope.patch" "02-float64-slope（既存データ再現用）"
else
  echo "  ・02-float64-slope はスキップ（APPLY_FLOAT64=0）"
fi

echo "=== 確認 ==="
printf "  _read_chunk : %s箇所（期待3）\n" "$(grep -c '_read_chunk' "$SP/csmap/process.py")"
printf "  nodata_mask : %s箇所（期待2）\n" "$(grep -c 'nodata_mask' "$SP/csmap/process.py")"
printf "  float64     : %s箇所（02適用時は2）\n" "$(grep -c 'float64' "$SP/csmap/calc.py" || true)"
"$VENV/bin/python" -m csmap --help > /dev/null && echo "  ✅ csmap が実行できます"

cat <<EOF

=== 準備完了 ===
以降のコマンドの前に、これを実行してください:

  export CSMAP_CMD="$VENV/bin/python -m csmap"

確認:
  bash scripts/03-csmap.sh <入力DEM.tif> <出力csmap.tif>
EOF
