# ブラウザ用ページ（日英対応）

- `index.html` … ファームウェア書き込み
- `layout.html` … MIDI配列変更（WebHID + VIA）

両方とも1ファイルに日本語と英語を同梱し、`html.en` クラスで切り替える。
ファイルを分けないのは、ファームウェアの二重化を避けるためと、
文言修正が片方だけ古くなるのを防ぐため。初回はブラウザの言語で自動判定し、
選択は localStorage に記憶する。

## 書き込みページ

`index.html` を Web サーバーに置くだけで動きます。**HTTPS が必要**です
（WebUSB は安全な接続でしか動きません。`http://localhost` は例外）。

- ファームウェアはページに埋め込み済み。別途ダウンロードは不要
- Vendor ID `0x2e3c` 以外の機器は弾く
- 内蔵フラッシュ（alt=0）を自動で選ぶ。オプションバイト領域には触らない
- 書き込み後の `stall` は正常終了として扱う

書き込み処理は [webdfu](https://github.com/devanlai/webdfu)
(Copyright (c) 2016, Devan Lai / ISC License) を使用。

## 作り直すとき

ファームウェアを更新したら、`index.html` の `FIRMWARE_B64` を
新しい `.bin` の base64 に差し替えてください。

## 免責事項の根拠（2026-09-03 確認）

ページ下部の「メーカー保証の対象外となる場合があります」という記載は、
Keychron 公式の保証規定に基づく。 https://www.keychron.com/pages/warranty

- 「Keychron が許可していないソフトウェアの改変を行った場合、保証は終了する」
  （the warranty will cease if you make modifications in the software not
  authorized by Keychron）
- 対象外項目に「非純正の修理・改造に起因する不具合」（non-factory
  repairs/modifications）

ただし Keychron 自身が QMK のソースと書き込み手順を公開しているため、
「公式ファームウェアの書き込み」と「第三者製ファームウェアの書き込み」で
扱いが異なる可能性がある。**この点は Keychron に確認していない。**
規定の文面は断定形だが、ページの記載は「場合があります」と留めてあり、
確認できていない範囲を断定しない表現になっている。
