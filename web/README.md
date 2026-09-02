# ブラウザ書き込みページ

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
