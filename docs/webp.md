# WebP化と配信

## なぜ WebP か

CS立体図タイルは 256×256 の **RGBA 8bit PNG** で、平均 63〜70KB と大きい。
WebP に変えることで容量を大幅に削減できる。

### 実測（サンプル60枚 / 5データセット × z16-18）

| 方式 | 削減率 | 判断 |
|---|---|---|
| PNG（現行） | — | |
| WebP 可逆 | 33% | 削減が足りない |
| PNG8 (256色) | 62% | 拡張子は変わらないが削減が足りない |
| **WebP q=95** | **78%** | **採用** |
| WebP q=90 | 84% | 実用範囲だが不要な画質低下 |
| WebP q=85 | 88% | 微地形テクスチャが劣化 |
| WebP q=80 | 90% | 同上 |

単一タイルでの実測（pref-nagano z17、元 109,846B）:

```
PNG8    41,387B
q=95    23,280B
q=90    16,060B
q=85    11,680B
q=80     8,670B
```

**q=95 を採用する。** 目視で元と区別がつかず、必要な削減量は達成できる。
CS立体図は微細な陰影そのものが情報なので、これ以上は落とさない。

---

## URLを変えずに配信する

タイルの拡張子が `.png` から `.webp` に変わると、参照している地図をすべて修正する必要がある。
**`.htaccess` で `.png` へのリクエストを `.webp` に振り替えれば、URLを変えずに済む。**

ブラウザは拡張子ではなく `Content-Type` で画像形式を判定するため、
`.png` のURLで WebP を返しても正しく表示される。

### 設置内容

配信ディレクトリ（例 `public_html/raster-tiles/`）に `.htaccess` を置く。

```apache
AddType image/webp .webp

<IfModule mod_rewrite.c>
RewriteEngine On
RewriteBase /raster-tiles/

# .png のリクエストに対し、同名の .webp があればそれを返す
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{DOCUMENT_ROOT}/raster-tiles/$1.webp -f
RewriteRule ^(.+)\.png$ $1.webp [L]
</IfModule>
```

`RewriteBase` と `RewriteCond` のパスは設置場所に合わせて変更する。

### 検証済みの挙動（Xserver / nginx + Apache）

| 検証項目 | 結果 |
|---|---|
| `.png` でリクエスト | HTTP 200 / `Content-Type: image/webp` |
| 取得した実体 | `RIFF … WebP, VP8, 256x256` |
| CORS ヘッダ | `access-control-allow-origin: *` が維持される |
| 存在しないタイル | HTTP 404（リライトは暴発しない） |
| `.webp` を直接リクエスト | HTTP 200 / `image/webp` |

CORSヘッダが維持される点は重要。他ドメインの地図から参照される場合に必要になる。

---

## 反映手順

**必ず `.htaccess` を先に置くこと。** PNGを削除してから設置すると、その間タイルが404になる。

```
1. .htaccess を設置          ← この時点ではPNGが優先されるので影響なし
2. WebPタイルをアップロード     ← まだPNGが返る
3. 動作確認（.png URLでWebPが返ることを確認）
4. PNGを削除                 ← ここでWebP配信に切り替わる
```

手順3の確認コマンド:

```bash
curl -sS -o /dev/null -w "%{http_code} %{content_type} %{size_download}\n" \
  "https://<host>/raster-tiles/<dataset>/<z>/<x>/<y>.png"
```

`200 image/webp <小さいサイズ>` が返れば成功。

---

## 想定されるリスク

**非ブラウザのクライアント**が `.png` URL で WebP を受け取った場合、
解釈できない可能性がある（QGIS、GDAL、独自スクリプトなど）。

アクセスログの User-Agent を確認して、ブラウザ以外の利用がないか調べておくこと。
referer が付かないアクセスが多いデータセットは特に注意する。

対応できない利用者がいる場合は、PNGを残したまま WebP を併置し、
`Accept` ヘッダで振り分ける方法もある（ただし容量削減効果は失われる）。

```apache
RewriteCond %{HTTP_ACCEPT} image/webp
RewriteCond %{DOCUMENT_ROOT}/raster-tiles/$1.webp -f
RewriteRule ^(.+)\.png$ $1.webp [L]
```
