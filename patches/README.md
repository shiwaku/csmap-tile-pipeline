# csmap-py へのパッチ

**本家の csmap-py は NoData（データの無い範囲）を透明化しない。**
パッチを当てないと、海・対象外の市町村・LiDARの欠測域が不透明に塗り潰され、
地図に重ねたとき下のレイヤが見えなくなる。

対象: [MIERUNE/csmap-py](https://github.com/MIERUNE/csmap-py) **v0.1.4**
（本家未取り込み。2025-01-07 時点の main で確認）

## パッチは2つ

| ファイル | 内容 | 本家テスト | 用途 |
|---|---|---|---|
| `01-nodata-transparency.patch` | NoData を透明にする | ✅ 3 passed | **必須** |
| `02-float64-slope.patch` | float32 オーバーフロー回避 | ❌ 3 failed | 既存データの再現時のみ |

**NoData の透明化には `01` だけで足りる。**
`02` は出力が丸め誤差レベルで変わり（最大1/255・該当画素0.000%）
本家のフィクスチャ比較を壊すため、本家への提案には含めない。
既存データセットを画素単位で再現したい場合のみ適用する
（適用しないと859万画素中27画素が相違）。

## 適用方法

```bash
python3 -m venv csmapenv
./csmapenv/bin/pip install csmap-py==0.1.4
cd csmapenv/lib/python3*/site-packages
patch -p1 < /path/to/patches/01-nodata-transparency.patch
patch -p1 < /path/to/patches/02-float64-slope.patch   # 任意
```

確認:

```bash
grep -c '_read_chunk'  csmap/process.py   # 3 (定義1 + 呼出2)
grep -c 'nodata_mask'  csmap/process.py   # 2
grep -c 'float64'      csmap/calc.py      # 2 (02を当てた場合)
```

## 変更内容（01）

1. `_read_chunk()` を追加し、`masked=True` + `filled(np.nan)` で NoData を NaN として読む
   - **整数型の DEM は float32 に昇格させる。** これが無いと
     `TypeError: Cannot convert fill_value nan to dtype int16` で落ちる
   - float64 の DEM は精度を落とさないようそのまま扱う
2. `_process_chunk()` で NaN の位置のアルファを 0 にする
   - 削られる縁の幅は入力 chunk と出力の形状差から求めるので、
     パディングやフィルタサイズの実装が変わっても追従する

## 検証結果

| 項目 | 結果 |
|---|---|
| 実データ（float32 / `NoData=1.70141e+38` / 全画素の29.8%がNoData） | 透明率 **0.0% → 29.63%**、既知の正解データと**画素単位で完全一致** |
| NoData値・型 6パターン | float32(−9999/0/NaN)・int16・int32・uint16 すべて正常 |
| 本家テストスイート | ✅ 3 passed（`01` のみ） |
| 並列処理（max_workers=4） | 逐次実行と**画素差0** |
| NoData宣言なしDEM | 退行なし |
| 性能 | 0.99秒 → 0.66秒 |
| メモリ | 220MB → 226MB（+2.5%） |

詳細は [../docs/nodata.md](../docs/nodata.md)。

## 前提

**DEM 側に NoData の宣言が必要。** 値は何でもよいが、`0` は標高0mと衝突するため避ける。
宣言が無い場合は `gdal_edit.py -a_nodata` 等で後付けする。

## 本家への提案

| ファイル | 内容 |
|---|---|
| [UPSTREAM-ISSUE.md](UPSTREAM-ISSUE.md) | issue の下書き |
| [UPSTREAM-PR.md](UPSTREAM-PR.md) | PR の下書き |

fork 済み: https://github.com/shiwaku/csmap-py （ブランチ `fix/nodata-transparency`、`01` のみ適用）
