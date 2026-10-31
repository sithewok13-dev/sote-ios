#pragma once

#import <Foundation/Foundation.h>

// The CHEAT button: turns all of SotE-Recomp's cheats on or off together by
// rewriting Documents/SOTE_CHEATS.INI, which the game re-reads within a
// second (infinite health, lives, ammo, missiles and vehicle health).
void sote_cheat_set(BOOL on);

// Plays a random clip, never the last one, from the "Cheat Sounds" folder in
// the Files app (mp3, m4a, wav, caf, aif): the player's own clips. With none
// there, plays the app's own built-in cheat sound.
BOOL sote_cheat_play_sound(void);
