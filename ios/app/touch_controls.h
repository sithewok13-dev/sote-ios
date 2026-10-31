#pragma once

#import <UIKit/UIKit.h>

// On-screen N64 controller drawn over the game, in the house style shared
// with the other ports (jk-files docs/HOUSE_STYLE.md, section 3):
//  - a floating stick in the lower left; drag anywhere else to look;
//  - A, B and the C buttons on the right, Z under L, L and R at the top;
//  - START at the bottom: a tap presses Start, a 0.45 s hold (ring) opens
//    the tray: GYRO, SENS, OPACITY, CAMERA, CHEAT, D-PAD, LOG;
//  - optional top-row buttons: CAMERA (tap a photo, slide sideways for a
//    burst), CHEAT (hold 0.5 s to switch the cheats) and LEVEL (cheat on).
// Settings are kept in NSUserDefaults under iosTouch* keys.
@interface SoteTouchControlsView : UIView

// Called when the tray's LOG button is tapped.
@property (nonatomic, copy) void (^toggleLog)(void);

@end

// Writes the player's on-foot control scheme (Modern by default) into the
// game's sote_controls.json. Call before the game starts.
void sote_touch_prepare_controls(NSURL *documents);
