// iOS implementation of sote_platform.h.

#include "sote_platform.h"
#include "sote_platform_ios.h"

#import <Foundation/Foundation.h>

#include <atomic>
#include <chrono>
#include <cmath>

#include "frontend.hpp"

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

    static std::atomic<int> level_jump{-1};

    void ios_request_level_jump(int event) {
        level_jump.store(event);
    }

    int take_level_jump() {
        return level_jump.exchange(-1);
    }

    static std::atomic<int64_t> message_drawn_ms{0};

    static int64_t steady_ms() {
        return std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now().time_since_epoch()).count();
    }

    void note_message_drawn() {
        message_drawn_ms.store(steady_ms());
    }

    bool ios_message_showing() {
        return steady_ms() - message_drawn_ms.load() < 250;
    }

    static std::atomic<bool> held{false};
    static std::atomic<float> player_x{NAN};
    static std::atomic<float> player_y{NAN};
    static std::atomic<float> player_z{NAN};

    void note_player_position(float x, float y, float z) {
        player_x.store(x);
        player_y.store(y);
        player_z.store(z);
    }

    static std::atomic<float> camera_data[6] = {NAN, NAN, NAN, NAN, NAN, NAN};

    void note_camera(float eye_x, float eye_y, float eye_z, float forward_x, float forward_y, float forward_z) {
        const float values[6] = {eye_x, eye_y, eye_z, forward_x, forward_y, forward_z};
        for (int i = 0; i < 6; i++) {
            camera_data[i].store(values[i]);
        }
    }

    bool ios_game_camera(float eye[3], float forward[3]) {
        bool valid = true;
        for (int i = 0; i < 3; i++) {
            eye[i] = camera_data[i].load();
            forward[i] = camera_data[i + 3].load();
            valid = valid && std::isfinite(eye[i]) && std::isfinite(forward[i]);
        }

        return valid && ((forward[0] * forward[0] + forward[1] * forward[1] + forward[2] * forward[2]) > 0.5f);
    }

    bool game_held() {
        return held.load();
    }

    void ios_set_game_held(bool hold) {
        held.store(hold);
    }

    bool ios_player_position(float *x, float *y, float *z) {
        *x = player_x.load();
        *y = player_y.load();
        *z = player_z.load();
        return std::isfinite(*x) && std::isfinite(*y) && std::isfinite(*z);
    }

    void ios_add_look(int x, int y) {
        sote::frontend::add_mouse_delta(x, y);
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
