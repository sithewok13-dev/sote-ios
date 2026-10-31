// iOS implementation of sote_platform.h.

#include "sote_platform.h"
#include "sote_platform_ios.h"

#import <Foundation/Foundation.h>

#include <atomic>
#include <chrono>

namespace sote::platform {
    static std::atomic<void *> game_view{nullptr};
    static std::atomic<void *> game_layer{nullptr};
    static std::atomic<int64_t> start_held_until_ms{0};

    static int64_t now_ms() {
        return std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now().time_since_epoch()).count();
    }

    void ios_press_start() {
        // Long enough for the game to poll it at least a few times.
        start_held_until_ms.store(now_ms() + 200);
    }

    void ios_set_game_view(void *view, void *layer) {
        game_layer.store(layer);
        game_view.store(view);
    }

    std::filesystem::path data_directory() {
        NSURL *documents = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
        return std::filesystem::path(documents.path.fileSystemRepresentation);
    }

    ultramodern::renderer::WindowHandle create_window() {
        ultramodern::renderer::WindowHandle handle{};
        handle.window = game_view.load();
        handle.view = game_layer.load();
        return handle;
    }

    void update_gfx() {}

    bool key_down(int virtual_key) {
        // Enter is the PC release's Start key.
        constexpr int VirtualKeyReturn = 0x0D;
        return (virtual_key == VirtualKeyReturn) && (now_ms() < start_held_until_ms.load());
    }
}
