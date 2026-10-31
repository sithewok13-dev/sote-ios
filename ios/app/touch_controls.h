#pragma once

#import <UIKit/UIKit.h>

// On-screen N64 controller drawn over the game: a floating analog stick on the
// left, A/B/Z and the C buttons on the right, L and R at the top corners, a
// D-pad above the stick and Start at the bottom. Every change is passed to the
// game through sote::platform::ios_set_touch_input.
@interface SoteTouchControlsView : UIView

// Called when the small "log" button at the top is tapped.
@property (nonatomic, copy) void (^toggleLog)(void);

@end
