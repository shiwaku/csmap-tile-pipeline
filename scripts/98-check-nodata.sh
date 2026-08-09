#!/bin/bash
# NoData（透明領域）が正しく設定されているか検証する
# 使い方: bash 98-check-nodata.sh <GeoTIFF または タイルディレクトリ>
#
# ラスタータイル最大の事故要因。NoDataが透明化されていないと、
# 海や範囲外が不透明に塗り潰されて下のレイヤが見えなくなる。
set -u
T="${1:?GeoTIFFまたはタイルディレクトリを指定してください}"

python3 - "$T" <<'PY'
import sys, os, glob
import numpy as np
from osgeo import gdal
gdal.UseExceptions()

t = sys.argv[1]

def report(path, arr_alpha, bands):
    tot = arr_alpha.size
    tr  = (arr_alpha == 0).sum() / tot * 100
    op  = (arr_alpha == 255).sum() / tot * 100
    print(f"  バンド数   : {bands}" + ("" if bands >= 4 else "  ⚠ アルファがありません"))
    print(f"  透明(0)    : {tr:5.1f}%")
    print(f"  不透明(255): {op:5.1f}%")
    print(f"  中間       : {100-tr-op:5.1f}%")
    if tr < 1.0:
        print(f"  ⚠ 透明領域がほぼありません({tr:.2f}%)。NoDataが未設定の可能性が高い。")
        print("    対象範囲が矩形いっぱいなら正常です。地域の形状と照らして判断してください。")
    elif tr > 95:
        print("  ⚠ ほぼ全面が透明です。データが入っていない可能性があります。")
    else:
        print("  ✅ 透明領域があります")

if os.path.isdir(t):
    fs = sorted(glob.glob(os.path.join(t, "**", "*.webp"), recursive=True)) \
       + sorted(glob.glob(os.path.join(t, "**", "*.png"), recursive=True))
    if not fs:
        print("タイルが見つかりません"); sys.exit(1)
    # 最も深いズームから最大200枚を抽出して集計
    fs = fs[-200:] if len(fs) > 200 else fs
    print(f"タイルディレクトリ: {t}")
    print(f"  検査枚数: {len(fs)}")
    tr_list, nb = [], set()
    for f in fs:
        ds = gdal.Open(f); nb.add(ds.RasterCount)
        if ds.RasterCount >= 4:
            a = ds.GetRasterBand(4).ReadAsArray()
            tr_list.append((a == 0).sum() / a.size * 100)
        ds = None
    # gdal2tiles は完全不透明のタイルをアルファ無し(3バンド)で出力する。これは正常な最適化。
    print(f"  バンド数: {sorted(nb)}" + ("" if min(nb) >= 4 else "  (3バンドは完全不透明タイルの最適化)"))
    if tr_list:
        arr = np.array(tr_list)
        print(f"  透明率  : 平均{arr.mean():5.1f}%  最小{arr.min():5.1f}%  最大{arr.max():5.1f}%")
        print(f"  完全不透明のタイル: {(arr==0).sum()}/{len(arr)}枚")
        print(f"  完全透明のタイル  : {(arr==100).sum()}/{len(arr)}枚")
        if arr.max() < 1.0:
            print(f"  ⚠ ほぼ全タイルが不透明です(最大{arr.max():.2f}%)。NoDataが透明化されていない可能性が高い。")
        else:
            print("  ✅ 透明領域を含むタイルがあります")
else:
    ds = gdal.Open(t)
    print(f"ファイル: {t}")
    print(f"  サイズ: {ds.RasterXSize} x {ds.RasterYSize}")
    for b in range(1, min(ds.RasterCount, 4) + 1):
        nd = ds.GetRasterBand(b).GetNoDataValue()
        if nd is not None:
            print(f"  Band{b} NoDataValue = {nd}")
    if ds.RasterCount >= 4:
        a = ds.GetRasterBand(4)
        # 間引き読み込みで概況を見る
        step = max(1, max(ds.RasterXSize, ds.RasterYSize) // 2000)
        arr = a.ReadAsArray(buf_xsize=ds.RasterXSize//step, buf_ysize=ds.RasterYSize//step)
        report(t, arr, ds.RasterCount)
    else:
        print(f"  バンド数: {ds.RasterCount}  ⚠ アルファがありません")
        print("    gdalwarp に -dstalpha を付ける、または元DEMのNoDataを確認してください。")
    ds = None
PY
