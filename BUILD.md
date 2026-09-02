# 自分で作る

ソースコードから自分でファームウェアを作る手順です。
**他のQMK対応キーボードをMIDIコントローラーにしたい場合も、ここを読んでください。**

---

## なぜ自分で作るのか

**理由は2つあります。**

**1つ目。** 他人が作ったファームウェアは、中身を確認できません。
キーボードのファームウェアは**キーボードに好きな文字を打たせることができる**ので、
悪意があれば何でもできてしまいます。自分で作れば、その心配がありません。

**2つ目。** 配列を変えたい、MIDIチャンネルを変えたい、
**別のキーボードでやりたい**、といった場合は自分で作るしかありません。

---

## 用意するもの

| | |
|---|---|
| 対象のキーボード | **QMK対応で、メーカーが設計図を公開しているもの。有線接続** |
| ビルド環境 | 約3GB。QMKのソースとコンパイラ |
| 時間 | 30分〜1時間（ほとんどダウンロード待ち） |

Claude Code などのAIに任せるのが楽です。この文書をそのまま読ませてください。

---

## 手順（C100 8K の場合）

### 1. ビルド環境を用意する

```
brew install qmk/qmk/qmk        # 信頼の確認を求められたら承認する
git clone --branch 2025q3 --depth 1 https://github.com/Keychron/qmk_firmware.git ~/qmk_keychron
cd ~/qmk_keychron
git submodule update --init --recursive --depth 1
```

Keychron 以外のキーボードなら、そのメーカーのリポジトリか、
本家 `qmk/qmk_firmware` を使ってください。

### 2. キーマップを置く

このリポジトリの `keymap/` の中身を、キーボードのフォルダにコピーします。

```
mkdir -p keyboards/keychron/c100_8k/keymaps/midi
cp <このリポジトリ>/keymap/* keyboards/keychron/c100_8k/keymaps/midi/
```

### 3. ビルド

```
qmk compile -kb keychron/c100_8k -km midi
```

`.build/keychron_c100_8k_midi.bin` ができます。

### 4. 書き込む

左上のキーを押しながらUSBを挿して、書き込みモードに入れてから：

```
dfu-util -d 2e3c:df11 -a 0 -s 0x08000000:leave -D .build/keychron_c100_8k_midi.bin
```

---

## 中身の説明

`keymap/` には3つのファイルしかありません。

### rules.mk

```make
MIDI_ENABLE = yes
VIA_ENABLE  = yes
```

**この2行だけです。** MIDI機能を足して、Keychron Launcher も使えるようにしています。

### config.h

```c
#define MIDI_ADVANCED
```

これも1行だけ。任意のノート番号を送れるようにするための指定です。

### keymap.c

「どのキーがどのノートか」の表と、MIDIを送る処理。全部で50行ほどです。

```c
enum pad_keycodes { PAD_FIRST = SAFE_RANGE, PAD_LAST = PAD_FIRST + 127 };
#define N(n) (PAD_FIRST + (n))

bool process_record_user(uint16_t keycode, keyrecord_t *record) {
    if (keycode >= PAD_FIRST && keycode <= PAD_LAST) {
        uint8_t note = (uint8_t)(keycode - PAD_FIRST);
        if (record->event.pressed) midi_send_noteon(&midi_device, 0, note, 127);
        else                       midi_send_noteoff(&midi_device, 0, note, 0);
        return false;
    }
    return true;
}
```

`N(36)` と書けば、そのキーがノート36を鳴らします。

---

## 変更のしかた

### 配列を変える

`keymap.c` の表の数字を書き換えるだけです。

### MIDIチャンネルを変える

`midi_send_noteon` / `midi_send_noteoff` の2番目の引数です。
`0` がチャンネル1、`1` がチャンネル2。

### キーボードの名前を変える（複数台使うとき）

`config.h` に足します。

```c
#undef  PRODUCT
#define PRODUCT "Keychron C100 A"
```

これで DAW の入力一覧に別々の名前で並びます。
2台目は `B`、3台目は `C` にしてください。

---

## 他のキーボードでやる場合

**変えるのは2か所だけ**です。

**1. 配置マクロの名前**

`keymap.c` の `LAYOUT_tkl_ansi(...)` の部分。
キーボードの `keyboard.json` を見れば、そのキーボードで使う名前が書いてあります。

**2. キーの数と並び順**

同じく `keyboard.json` の `layouts` に、
「何番目のキーが基板のどこか」が全部載っています。QMKの配置マクロは
**左上から右へ、行ごとに下へ**の順番なので、その順にノート番号を並べます。

**それ以外は全部同じです。** MIDIを送る処理も、`rules.mk` も、`config.h` も、
キーボードが変わっても変える必要がありません。

### 条件

- **QMK対応で、メーカーが設計図（keyboard.json）を公開している**こと
- **有線接続**であること。Bluetooth や 2.4GHz では MIDI を送れません
- チップに**空き容量**があること（MIDI機能でおよそ6KB増えます）

---

## Keychron製キーボード特有の落とし穴

**私が実際に踏んだものです。** 同じところで詰まらないように書いておきます。

### 1. `NKRO_ENABLE = no` にしてはいけない

Keychron のコードは NKRO が有効な前提で書かれています。無効にすると
`quantum/action_util.c` が、宣言されていない変数を参照してコンパイルエラーになります。

### 2. `DEBOUNCE` を上書きしてはいけない ← 一番危険

Keychron は独自のデバウンス実装を使っていて、ボードの設定値を前提にしています。
キーマップの `config.h` で `#define DEBOUNCE 5` などとすると、
**ビルドも書き込みも成功するのに、キーを押しても一切反応しなくなります。**
エラーが出ないので、原因に辿り着くのが非常に困難です。

**結論：`config.h` には `#define MIDI_ADVANCED` だけ書く。**
チャタリングの調整は Keychron Launcher の「アドバンスモード」から行ってください。

### 3. `#include "qmk_midi.h"` が必要

`midi_device` はこのヘッダで宣言されています。`QMK_KEYBOARD_H` だけでは足りません。

### 4. Launcher のファームウェア更新機能では書き込めない

Keychron 公式が配信するファームウェアしか扱えません。自作のファイルを選ぶ機能は
ありません。`dfu-util` か QMK Toolbox を使ってください。

---

## 動作確認の方法

書き込んだあと、MIDIが出ているかを確かめるには、
DAWを開く前に**MIDIモニター**で見るのが確実です。

- macOS：`Audio MIDI設定` や、MIDIモニター系のアプリ
- どのDAWでも：MIDI入力を有効にして、トラックを録音待機にすれば入力ランプが光ります

**ノートが出ているのに音が鳴らない場合は、DAW側の設定の問題**です。
