// iOS implementation of sote_platform.h.

#include "sote_platform.h"
#include "sote_platform_ios.h"

#import <Foundation/Foundation.h>

#include <atomic>

namespace sote::platform {
    static std::atomic<void *> game_view{nullptr};
    static std::atomic<void *> game_layer{nullptr};
    static std::atomic<uint32_t> touch_buttons{0};
    static std::atomic<float> touch_x{0.0f};
    static std::atomic<float> touch_y{0.0f};

    void ios_set_touch_input(uint16_t buttons, float x, float y) {
        touch_x.store(x);
        touch_y.store(y);
        touch_buttons.store(buttons);
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

    bool key_down(int) {
        return false;
    }

    bool touch_input(uint16_t *buttons, float *x, float *y) {
        *buttons = static_cast<uint16_t>(touch_buttons.load());
        *x = touch_x.load();
        *y = touch_y.load();
        return (*buttons != 0) || (*x != 0.0f) || (*y != 0.0f);
    }
}
