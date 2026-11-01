#pragma once

// What SotE-Recomp's game layer needs from the iOS app. Implemented in
// ios/game/sote_platform_ios.mm; used by the iOS branches that
// patches/sote-recomp adds to main.cpp, frontend.cpp and rt64_renderer.cpp.

#include <cstdint>
#include <filesystem>

#include "ultramodern/renderer_context.hpp"

namespace sote::platform {
    // Where the ROM, configuration, saves and logs live: the app's Documents
    // folder, which the Files app shows as "SotE".
    std::filesystem::path data_directory();

    // The Metal view the game draws into: {UIView*, CAMetalLayer*}.
    ultramodern::renderer::WindowHandle create_window();

    // Called every frame from the game's graphics thread. iOS has no message
    // pump to run there; UIKit's run loop lives on the main thread.
    void update_gfx();

    // Keyboard state for a Win32 virtual-key code (hardware keyboards later).
    bool key_down(int virtual_key);

    // On-screen controls: N64 button bits and a stick in [-1, 1] (up is +y).
    // Returns false when no control is held.
    bool touch_input(uint16_t *buttons, float *x, float *y);

    // The event a level selector asked to jump to, once, or -1. Polled from
    // the game thread every VI.
    int take_level_jump();

    // Called from the game thread each time a visible message box's text is
    // drawn, with its top in N64 pixels (0-240).
    void note_message_drawn(int top);

    // Called from the game thread every frame with Dash's world position on
    // foot (NaN otherwise), for the freeze camera.
    void note_player_position(float x, float y, float z);

    // Called from the game thread every frame with the game camera's eye and
    // forward direction in world units (z up; NaN when there is none).
    void note_camera(float eye_x, float eye_y, float eye_z, float forward_x, float forward_y, float forward_z);

    // True while the app holds the game still (freeze camera, selfies); the
    // game thread waits while it is.
    bool game_held();
}
