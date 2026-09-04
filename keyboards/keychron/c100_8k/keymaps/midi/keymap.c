/* Keychron C100 8K -- all 100 keys as MIDI pads.
 *
 * Channel 1, fixed velocity 127. The bottom-left 8x8 follows the MIDI Fighter 64
 * layout: each 4x4 bank is a contiguous block of 16 notes, which is exactly one
 * Ableton Drum Rack page (36-51 / 52-67 / 68-83 / 84-99).
 *
 * Notes as they sit on the keyboard (top row first):
 *
 *   104 105 106 107 | 112 113 114 115 |  35  33
 *   100 101 102 103 | 108 109 110 111 |  34  32
 *    64  65  66  67 |  96  97  98  99 |  31  27
 *    60  61  62  63 |  92  93  94  95 |  30  26
 *    56  57  58  59 |  88  89  90  91 |  29  25
 *    52  53  54  55 |  84  85  86  87 |  28  24
 *    48  49  50  51 |  80  81  82  83 |  23  19
 *    44  45  46  47 |  76  77  78  79 |  22  18
 *    40  41  42  43 |  72  73  74  75 |  21  17
 *    36  37  38  39 |  68  69  70  71 |  20  16
 *
 * Unlike the userspace bridge this replaces, there is no six-key limit here:
 * these are MIDI notes, not HID keyboard usages, so every pad can be held at once.
 */

#include QMK_KEYBOARD_H
#include "qmk_midi.h"   /* declares midi_device */

#define MIDI_PAD_CHANNEL  0    /* 0 = MIDI channel 1 */
#define MIDI_PAD_VELOCITY 127  /* mechanical switches are on/off */

enum pad_keycodes {
    PAD_FIRST = SAFE_RANGE,
    PAD_LAST  = PAD_FIRST + 127,
    PAD_SAFE_RANGE,
};

/* N(n) -> the keycode that plays MIDI note n */
#define N(n) (PAD_FIRST + (n))

const uint16_t PROGMEM keymaps[][MATRIX_ROWS][MATRIX_COLS] = {
    [0] = LAYOUT_tkl_ansi(
        N(104), N(105), N(106), N(107), N(112), N(113), N(114), N(115), N( 35), N( 33),
        N(100), N(101), N(102), N(103), N(108), N(109), N(110), N(111), N( 34), N( 32),
        N( 64), N( 65), N( 66), N( 67), N( 96), N( 97), N( 98), N( 99), N( 31), N( 27),
        N( 60), N( 61), N( 62), N( 63), N( 92), N( 93), N( 94), N( 95), N( 30), N( 26),
        N( 56), N( 57), N( 58), N( 59), N( 88), N( 89), N( 90), N( 91), N( 29), N( 25),
        N( 52), N( 53), N( 54), N( 55), N( 84), N( 85), N( 86), N( 87), N( 28), N( 24),
        N( 48), N( 49), N( 50), N( 51), N( 80), N( 81), N( 82), N( 83), N( 23), N( 19),
        N( 44), N( 45), N( 46), N( 47), N( 76), N( 77), N( 78), N( 79), N( 22), N( 18),
        N( 40), N( 41), N( 42), N( 43), N( 72), N( 73), N( 74), N( 75), N( 21), N( 17),
        N( 36), N( 37), N( 38), N( 39), N( 68), N( 69), N( 70), N( 71), N( 20), N( 16)
    ),
};

/* ---- 単色リアクティブ系エフェクトをグラデーションにする ----
 *
 * リアクティブ・マルチネクサスなどは、色を1つしか持っていない。
 *   hsv.h = rgb_matrix_config.hsv.h + dy / 4;
 * QMK には時間で色相を回すビルド設定 (RGB_MATRIX_SOLID_REACTIVE_GRADIENT_MODE)
 * もあるが、それを入れると固定色に戻せなくなるうえ、速度も選べない。
 *
 * そこで色相そのものをゆっくり書き換える。エフェクトの実装には手を触れないので、
 * Keychron Launcher のエフェクト一覧もそのまま使える。
 * 対象は単色のリアクティブ系だけ。他のエフェクトは今まで通り。
 *
 * EEPROM に書くと寿命を削るので、必ず noeeprom 版を使うこと。 */
#ifdef RGB_MATRIX_ENABLE

/* 1段進むまでの時間。Keychron Launcher の速度スライダーで変えられるようにする。
 *   スライダー最大 →  10ms → 一周 約2.6秒
 *   スライダー中間 →  70ms → 一周 約18秒
 *   スライダー最小 → 130ms → 一周 約33秒
 * 書き換えが速すぎると負荷になるので、下限は 10ms で止める。 */
static uint16_t hue_step_ms(void) {
    return 10 + (uint16_t)((255 - rgb_matrix_get_speed()) * 120) / 255;
}

static bool hue_should_drift(void) {
    if (!rgb_matrix_is_enabled()) return false;
    switch (rgb_matrix_get_mode()) {
#    ifdef ENABLE_RGB_MATRIX_SOLID_REACTIVE_SIMPLE
        case RGB_MATRIX_SOLID_REACTIVE_SIMPLE:
#    endif
#    ifdef ENABLE_RGB_MATRIX_SOLID_REACTIVE_MULTIWIDE
        case RGB_MATRIX_SOLID_REACTIVE_MULTIWIDE:
#    endif
#    ifdef ENABLE_RGB_MATRIX_SOLID_REACTIVE_MULTINEXUS
        case RGB_MATRIX_SOLID_REACTIVE_MULTINEXUS:
#    endif
            return true;
        default:
            return false;
    }
}

void housekeeping_task_user(void) {
    static uint16_t last = 0;
    if (!hue_should_drift()) return;
    if (timer_elapsed(last) < hue_step_ms()) return;
    last = timer_read();
    rgb_matrix_sethsv_noeeprom(rgb_matrix_get_hue() + 1,
                               rgb_matrix_get_sat(),
                               rgb_matrix_get_val());
}

#endif /* RGB_MATRIX_ENABLE */

bool process_record_user(uint16_t keycode, keyrecord_t *record) {
    if (keycode >= PAD_FIRST && keycode <= PAD_LAST) {
        uint8_t note = (uint8_t)(keycode - PAD_FIRST);
        if (record->event.pressed) {
            midi_send_noteon(&midi_device, MIDI_PAD_CHANNEL, note, MIDI_PAD_VELOCITY);
        } else {
            midi_send_noteoff(&midi_device, MIDI_PAD_CHANNEL, note, 0);
        }
        return false;   /* never emit a keyboard report for a pad */
    }
    return true;
}
