#pragma once

/* Advanced MIDI gives midi_send_noteon/noteoff with arbitrary note numbers.
 * Without it you only get QMK's two-octave MI_* keycodes. */
#define MIDI_ADVANCED

/* Do NOT override DEBOUNCE here. Keychron uses its own debounce implementation
 * (keyboards/keychron/common/debounce/) tuned around the board's value of 30;
 * forcing it to 5 stopped key presses registering at all. */
