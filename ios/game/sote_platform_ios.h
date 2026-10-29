#pragma once

namespace sote::platform {
    // Called by the app before the game starts: the UIView the game draws in
    // and its CAMetalLayer.
    void ios_set_game_view(void *view, void *layer);
}

// SotE-Recomp's main(), renamed by patches/sote-recomp for iOS. Blocks until
// the game exits, so the app runs it on its own thread.
int sote_main(int argc, char **argv);
