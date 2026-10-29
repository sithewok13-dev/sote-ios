#pragma once

// What SotE-Recomp's game layer needs from the iOS app. Implemented in
// ios/game/sote_platform_ios.mm; used by the iOS branches that
// patches/sote-recomp adds to main.cpp, frontend.cpp and rt64_renderer.cpp.

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
}
