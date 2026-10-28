#pragma once

#include <memory>

namespace sote {
    // Smallest useful plume program: clears the swap chain each frame. Proves
    // plume's Metal backend and the UIKit glue work before RT64 sits on top.
    class PlumeClear {
    public:
        // window is the UIView that owns layer, a CAMetalLayer.
        static std::unique_ptr<PlumeClear> create(void *window, void *layer);
        virtual ~PlumeClear() = default;
        virtual void resize() = 0;
        virtual void render(float red, float green, float blue) = 0;
    };
}
