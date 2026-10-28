//
// UIKit replacement for plume's AppKit-only plume_apple.mm.
//
// plume's Metal backend takes the CAMetalLayer from RenderWindow::view and
// only uses CocoaWindow for the drawable size and refresh rate. On iOS,
// RenderWindow::window holds the UIView that owns the layer.
//
// Based on plume_apple.mm, Copyright (c) 2024 renderbag and contributors,
// MIT license (see third_party/rt64/src/contrib/plume/LICENSE).
//

#include "plume_apple.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#include <cmath>

namespace plume {
    RenderDeviceVendor getRenderDeviceVendor(uint64_t registryID) {
        // Every iOS GPU is Apple's, and IOKit isn't public API on iOS.
        (void)registryID;
        return RenderDeviceVendor::APPLE;
    }

    static CGFloat getScaleFactor(UIView *view) {
#ifdef PLUME_APPLE_RETINA_ENABLED
        return view.contentScaleFactor;
#else
        (void)view;
        return 1.0f;
#endif
    }

    static CocoaWindowAttributes readAttributes(UIView *view) {
        const CGRect bounds = view.bounds;
        const CGFloat scaleFactor = getScaleFactor(view);
        CocoaWindowAttributes attributes;
        attributes.x = (int)round(bounds.origin.x);
        attributes.y = (int)round(bounds.origin.y);
        attributes.width = (int)round(bounds.size.width * scaleFactor);
        attributes.height = (int)round(bounds.size.height * scaleFactor);
        return attributes;
    }

    static int readRefreshRate(UIView *view) {
        UIScreen *screen = view.window.windowScene.screen;
        if (screen == nil) {
            screen = [UIScreen mainScreen];
        }

        return (int)screen.maximumFramesPerSecond;
    }

    // MARK: - CocoaWindow

    CocoaWindow::CocoaWindow(void* window)
        : windowHandle(window), cachedRefreshRate(0) {
        cachedAttributes = {0, 0, 0, 0};

        if ([NSThread isMainThread]) {
            UIView *view = (__bridge UIView *)windowHandle;
            cachedAttributes = readAttributes(view);
            cachedRefreshRate.store(readRefreshRate(view));
        } else {
            updateWindowAttributesInternal(true);
            updateRefreshRateInternal(true);
        }
    }

    CocoaWindow::~CocoaWindow() {}

    void CocoaWindow::updateWindowAttributesInternal(bool forceSync) {
        auto updateBlock = ^{
            UIView *view = (__bridge UIView *)windowHandle;
            CocoaWindowAttributes attributes = readAttributes(view);

            std::lock_guard<std::mutex> lock(attributesMutex);
            cachedAttributes = attributes;
        };

        if (forceSync) {
            dispatch_sync(dispatch_get_main_queue(), updateBlock);
        } else {
            dispatch_async(dispatch_get_main_queue(), updateBlock);
        }
    }

    void CocoaWindow::updateRefreshRateInternal(bool forceSync) {
        auto updateBlock = ^{
            UIView *view = (__bridge UIView *)windowHandle;
            cachedRefreshRate.store(readRefreshRate(view));
        };

        if (forceSync) {
            dispatch_sync(dispatch_get_main_queue(), updateBlock);
        } else {
            dispatch_async(dispatch_get_main_queue(), updateBlock);
        }
    }

    void CocoaWindow::getWindowAttributes(CocoaWindowAttributes* attributes) const {
        if ([NSThread isMainThread]) {
            UIView *view = (__bridge UIView *)windowHandle;
            std::lock_guard<std::mutex> lock(attributesMutex);
            const_cast<CocoaWindow*>(this)->cachedAttributes = readAttributes(view);
            *attributes = cachedAttributes;
        } else {
            {
                std::lock_guard<std::mutex> lock(attributesMutex);
                *attributes = cachedAttributes;
            }

            const_cast<CocoaWindow*>(this)->updateWindowAttributesInternal(false);
        }
    }

    int CocoaWindow::getRefreshRate() const {
        if ([NSThread isMainThread]) {
            UIView *view = (__bridge UIView *)windowHandle;
            int freshRate = readRefreshRate(view);
            const_cast<CocoaWindow*>(this)->cachedRefreshRate.store(freshRate);
            return freshRate;
        } else {
            int rate = cachedRefreshRate.load();
            const_cast<CocoaWindow*>(this)->updateRefreshRateInternal(false);
            return rate;
        }
    }

    void CocoaWindow::toggleFullscreen() {
        // iOS apps are always full screen.
    }
}
