# MIDI と、Keychron Launcher 用の VIA を両方有効にする。
# 余計な設定は書かないこと:
#   NKRO_ENABLE = no  -> Keychron のコードがビルド不能になる
#   DEBOUNCE の上書き -> ビルドは通るがキー入力が一切登録されなくなる
MIDI_ENABLE = yes
VIA_ENABLE  = yes
