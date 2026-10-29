// iOS implementation of sote_platform.h.

#include "sote_platform.h"
#include "sote_platform_ios.h"

#import <Foundation/Foundation.h>

#include <atomic>

namespace sote::platform {
    static std::atomic<void *> game_view{nullptr};
    static std::atomic<void *> game_layer{nullptr};

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

    bool key_down(int) {
        return false;
    }
}
