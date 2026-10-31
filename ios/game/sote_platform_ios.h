#pragma once

#include <cstdint>

namespace sote::platform {
    // Called by the app before the game starts: the UIView the game draws in
    // and its CAMetalLayer.
    void ios_set_game_view(void *view, void *layer);

    // Called by the on-screen controls whenever they change: N64 button bits
    // and a stick in [-1, 1].
    void ios_set_touch_input(uint16_t buttons, float x, float y);

    // Asks the game to jump to an event record (the start of a level).
    void ios_request_level_jump(int event);

    // Relative look from touch drags and the gyro, in mouse counts. Feeds the
    // game's own mouse look (Modern on foot, and vehicle steering).
    void ios_add_look(int x, int y);

    // True while the game is drawing a message box (Start dismisses it).
    bool ios_message_showing();

    // Holds or releases the game (freeze camera, selfies).
    void ios_set_game_held(bool held);

    // Dash's latest world position on foot; false when not on foot.
    bool ios_player_position(float *x, float *y, float *z);
}

// SotE-Recomp's main(), renamed by patches/sote-recomp for iOS. Blocks until
// the game exits, so the app runs it on its own thread.
int sote_main(int argc, char **argv);
