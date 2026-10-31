// On-screen N64 controller (see touch_controls.h).

#import "touch_controls.h"

#include <cmath>
#include <vector>

#include "sote_platform_ios.h"

namespace {
    // N64 controller button bits, as SotE-Recomp's frontend uses them.
    constexpr uint16_t N64A = 0x8000;
    constexpr uint16_t N64B = 0x4000;
    constexpr uint16_t N64Z = 0x2000;
    constexpr uint16_t N64Start = 0x1000;
    constexpr uint16_t N64DUp = 0x0800;
    constexpr uint16_t N64DDown = 0x0400;
    constexpr uint16_t N64DLeft = 0x0200;
    constexpr uint16_t N64DRight = 0x0100;
    constexpr uint16_t N64L = 0x0020;
    constexpr uint16_t N64R = 0x0010;
    constexpr uint16_t N64CUp = 0x0008;
    constexpr uint16_t N64CDown = 0x0004;
    constexpr uint16_t N64CLeft = 0x0002;
    constexpr uint16_t N64CRight = 0x0001;

    // How far the stick's knob travels from its base, in points.
    constexpr CGFloat StickRange = 56.0;
    constexpr CGFloat StickDeadZone = 0.12;

    struct Button {
        uint16_t bit;
        NSString *label;
        UIColor *color;
        CGFloat radius;
        CGPoint center;
        CAShapeLayer *shape;
        CATextLayer *text;
    };

    CGFloat distance(CGPoint a, CGPoint b) {
        return std::hypot(a.x - b.x, a.y - b.y);
    }
}

@implementation SoteTouchControlsView {
    std::vector<Button> _buttons;
    NSMutableSet<UITouch *> *_touches;
    UITouch *_stickTouch;
    CGPoint _stickHome;
    CGPoint _stickOrigin;
    CGPoint _stickKnob;
    CGRect _stickArea;
    CAShapeLayer *_stickBase;
    CAShapeLayer *_stickKnobLayer;
    CGPoint _logCenter;
    CATextLayer *_logText;
    uint16_t _pressed;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self == nil) {
        return nil;
    }

    self.backgroundColor = UIColor.clearColor;
    self.multipleTouchEnabled = YES;
    _touches = [NSMutableSet set];

    UIColor *gray = [UIColor colorWithWhite:0.85 alpha:1.0];
    UIColor *green = [UIColor colorWithRed:0.25 green:0.85 blue:0.35 alpha:1.0];
    UIColor *blue = [UIColor colorWithRed:0.30 green:0.55 blue:1.00 alpha:1.0];
    UIColor *yellow = [UIColor colorWithRed:1.00 green:0.85 blue:0.20 alpha:1.0];
    UIColor *red = [UIColor colorWithRed:1.00 green:0.35 blue:0.30 alpha:1.0];
    _buttons = {
        { N64A, @"A", green, 36 },
        { N64B, @"B", blue, 30 },
        { N64Z, @"Z", gray, 28 },
        { N64CUp, @"▲", yellow, 18 },
        { N64CDown, @"▼", yellow, 18 },
        { N64CLeft, @"◀", yellow, 18 },
        { N64CRight, @"▶", yellow, 18 },
        { N64L, @"L", gray, 26 },
        { N64R, @"R", gray, 26 },
        { N64Start, @"START", red, 24 },
        { N64DUp, @"↑", gray, 17 },
        { N64DDown, @"↓", gray, 17 },
        { N64DLeft, @"←", gray, 17 },
        { N64DRight, @"→", gray, 17 },
    };

    for (Button &button : _buttons) {
        button.shape = [CAShapeLayer layer];
        button.shape.lineWidth = 2.0;
        [self.layer addSublayer:button.shape];
        button.text = [self textLayer:button.label size:(button.radius > 20 ? 16 : 12)];
        [self.layer addSublayer:button.text];
    }

    _stickBase = [CAShapeLayer layer];
    _stickBase.fillColor = [UIColor colorWithWhite:1.0 alpha:0.10].CGColor;
    _stickBase.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.35].CGColor;
    _stickBase.lineWidth = 2.0;
    [self.layer addSublayer:_stickBase];
    _stickKnobLayer = [CAShapeLayer layer];
    _stickKnobLayer.fillColor = [UIColor colorWithWhite:1.0 alpha:0.35].CGColor;
    [self.layer addSublayer:_stickKnobLayer];

    _logText = [self textLayer:@"log" size:11];
    _logText.opacity = 0.5;
    [self.layer addSublayer:_logText];
    return self;
}

- (CATextLayer *)textLayer:(NSString *)string size:(CGFloat)size {
    CATextLayer *text = [CATextLayer layer];
    text.string = string;
    text.fontSize = size;
    text.font = (__bridge CFTypeRef)[UIFont boldSystemFontOfSize:size].fontName;
    text.foregroundColor = [UIColor colorWithWhite:1.0 alpha:0.85].CGColor;
    text.alignmentMode = kCAAlignmentCenter;
    text.contentsScale = UIScreen.mainScreen.scale;
    return text;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    const UIEdgeInsets insets = self.safeAreaInsets;
    const CGFloat left = insets.left + 24;
    const CGFloat right = self.bounds.size.width - insets.right - 24;
    const CGFloat top = insets.top + 16;
    const CGFloat bottom = self.bounds.size.height - insets.bottom - 16;
    const CGFloat midX = CGRectGetMidX(self.bounds);

    // Right hand: A and B like the N64, Z left of them, C buttons above.
    const CGPoint a = CGPointMake(right - 46, bottom - 60);
    const CGPoint c = CGPointMake(right - 70, bottom - 200);
    const CGPoint dpad = CGPointMake(left + 60, top + 120);
    const CGPoint centers[] = {
        a,                                      // A
        CGPointMake(a.x - 78, a.y - 46),        // B
        CGPointMake(a.x - 160, a.y + 10),       // Z
        CGPointMake(c.x, c.y - 34),             // C up
        CGPointMake(c.x, c.y + 34),             // C down
        CGPointMake(c.x - 34, c.y),             // C left
        CGPointMake(c.x + 34, c.y),             // C right
        CGPointMake(left + 40, top + 30),       // L
        CGPointMake(right - 40, top + 30),      // R
        CGPointMake(midX, bottom - 16),         // Start
        CGPointMake(dpad.x, dpad.y - 30),       // D-pad up
        CGPointMake(dpad.x, dpad.y + 30),       // D-pad down
        CGPointMake(dpad.x - 30, dpad.y),       // D-pad left
        CGPointMake(dpad.x + 30, dpad.y),       // D-pad right
    };

    for (size_t i = 0; i < _buttons.size(); i++) {
        Button &button = _buttons[i];
        button.center = centers[i];
        const CGFloat r = button.radius;
        const CGRect rect = CGRectMake(button.center.x - r, button.center.y - r, 2 * r, 2 * r);
        const bool pill = (button.bit == N64Start) || (button.bit == N64L) || (button.bit == N64R);
        UIBezierPath *path = pill ?
            [UIBezierPath bezierPathWithRoundedRect:CGRectInset(rect, -r * 0.6, r * 0.25) cornerRadius:r * 0.75] :
            [UIBezierPath bezierPathWithOvalInRect:rect];
        button.shape.path = path.CGPath;
        const CGFloat textHeight = button.text.fontSize * 1.25;
        button.text.frame = CGRectMake(button.center.x - r * 1.6, button.center.y - textHeight / 2, r * 3.2, textHeight);
    }

    // The stick floats: it starts wherever a finger lands in the lower left
    // of the screen, and rests here when nothing holds it.
    _stickHome = CGPointMake(left + 90, bottom - 90);
    _stickArea = CGRectMake(0, top + 170, midX - 60, self.bounds.size.height - top - 170);
    if (_stickTouch == nil) {
        _stickOrigin = _stickHome;
        _stickKnob = _stickHome;
    }

    _logCenter = CGPointMake(midX, top + 6);
    _logText.frame = CGRectMake(_logCenter.x - 30, _logCenter.y - 8, 60, 16);
    [self redraw];
}

- (void)redraw {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (Button &button : _buttons) {
        const bool down = (_pressed & button.bit) != 0;
        button.shape.fillColor = [button.color colorWithAlphaComponent:(down ? 0.55 : 0.18)].CGColor;
        button.shape.strokeColor = [button.color colorWithAlphaComponent:0.6].CGColor;
    }

    const CGFloat baseRadius = StickRange + 14;
    _stickBase.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(_stickOrigin.x - baseRadius, _stickOrigin.y - baseRadius, 2 * baseRadius, 2 * baseRadius)].CGPath;
    _stickKnobLayer.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(_stickKnob.x - 26, _stickKnob.y - 26, 52, 52)].CGPath;
    [CATransaction commit];
}

// The button under a point, allowing a little slack around each one.
- (uint16_t)buttonsAt:(CGPoint)point {
    uint16_t bits = 0;
    for (const Button &button : _buttons) {
        const CGFloat slack = (button.bit == N64Start || button.bit == N64L || button.bit == N64R) ? 1.6 : 1.25;
        if (distance(point, button.center) <= button.radius * slack) {
            bits |= button.bit;
        }
    }

    return bits;
}

- (void)update {
    uint16_t bits = 0;
    for (UITouch *touch in _touches) {
        if (touch != _stickTouch) {
            bits |= [self buttonsAt:[touch locationInView:self]];
        }
    }

    float x = 0.0f;
    float y = 0.0f;
    if (_stickTouch != nil) {
        const CGPoint p = [_stickTouch locationInView:self];
        CGFloat dx = p.x - _stickOrigin.x;
        CGFloat dy = p.y - _stickOrigin.y;
        const CGFloat length = std::hypot(dx, dy);
        if (length > StickRange) {
            dx *= StickRange / length;
            dy *= StickRange / length;
        }

        _stickKnob = CGPointMake(_stickOrigin.x + dx, _stickOrigin.y + dy);
        if (std::hypot(dx, dy) / StickRange > StickDeadZone) {
            x = float(dx / StickRange);
            y = float(-dy / StickRange);
        }
    }
    else {
        _stickOrigin = _stickHome;
        _stickKnob = _stickHome;
    }

    _pressed = bits;
    sote::platform::ios_set_touch_input(bits, x, y);
    [self redraw];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    for (UITouch *touch in touches) {
        const CGPoint p = [touch locationInView:self];
        if (distance(p, _logCenter) < 24) {
            if (self.toggleLog != nil) {
                self.toggleLog();
            }

            continue;
        }

        if ((_stickTouch == nil) && CGRectContainsPoint(_stickArea, p) && ([self buttonsAt:p] == 0)) {
            _stickTouch = touch;
            _stickOrigin = p;
        }

        [_touches addObject:touch];
    }

    [self update];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self update];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    for (UITouch *touch in touches) {
        [_touches removeObject:touch];
        if (touch == _stickTouch) {
            _stickTouch = nil;
        }
    }

    [self update];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self touchesEnded:touches withEvent:event];
}

@end
