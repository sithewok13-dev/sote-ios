// On-screen N64 controller, tray and extras (see touch_controls.h).

#import "touch_controls.h"

#import <AudioToolbox/AudioToolbox.h>
#import <CoreMotion/CoreMotion.h>

#include <algorithm>
#include <atomic>
#include <cmath>
#include <tuple>
#include <unordered_map>
#include <vector>

#include "controls_menu.hpp"
#include "ios_cheat.h"
#include "menu_skin.hpp"
#include "ios_photos.h"
#include "sote_platform_ios.h"

// Defined by patches/rt64/0004-ios-freeze-camera.patch.
namespace RT64 {
    extern std::atomic<bool> iosFreezeRequested;
    extern std::atomic<bool> iosFreezeActive;
    extern std::atomic<bool> iosFreezeHasPivot;
    extern std::atomic<float> iosFreezePivot[3];
    extern std::atomic<bool> iosFreezeHasEye;
    extern std::atomic<float> iosFreezeEye[3];
    extern std::atomic<float> iosFreezeForward[3];
    extern std::atomic<float> iosFreezeYaw;
    extern std::atomic<float> iosFreezePitch;
    extern std::atomic<float> iosFreezeZoom;
    extern std::atomic<float> iosFreezePanX;
    extern std::atomic<float> iosFreezePanY;
}

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

    // House style values (HOUSE_STYLE.md 3.1).
    constexpr CGFloat IdleAlpha = 0.65;
    constexpr CGFloat TouchSlop = 6.0;
    constexpr CGFloat StickRadius = 60.0;
    constexpr CGFloat StickKnob = 24.0;
    constexpr CGFloat StickDeadZone = 0.15;
    constexpr CGFloat StickAreaFraction = 0.42;
    constexpr double MenuHold = 0.45;
    constexpr double CheatHold = 0.5;
    constexpr double StartPulse = 0.15;
    constexpr double MenuPulse = 0.1;
    constexpr double MenuPulseGap = 0.06;
    constexpr double MenuTapTime = 0.35;
    constexpr CGFloat MenuSwipeStep = 40.0;
    constexpr CGFloat HoldMoveLimit = 12.0;
    constexpr CGFloat TrayRadius = 20.0;
    constexpr CGFloat TrayStep = 80.0;
    constexpr CGFloat BurstSlide = 10.0;
    constexpr double BurstPeriod = 0.2;
    constexpr int BurstMax = 10;
    constexpr double ToastTime = 1.6;

    // Freeze camera and selfies (house style: settle 0.35 s, show 0.9 s).
    constexpr double CameraHold = 0.5;
    constexpr CGFloat CameraSwipe = 36.0;
    constexpr double FreezeSettle = 0.35;
    constexpr double ShotSettle = 0.2;
    constexpr double ShotGap = 0.45;
    constexpr double ShotShow = 0.9;
    constexpr double FreezeTimeout = 1.5;
    constexpr float OrbitRadiansPerPoint = 0.3f * float(M_PI) / 180.0f;
    constexpr int SelfieCounts[] = { 1, 3, 5 };

    // Look: mouse counts per point dragged, and per degree the phone turns,
    // both times SENS (the game turns 0.12 degrees per count).
    constexpr CGFloat LookCountsPerPoint = 3.0;
    constexpr double GyroCountsPerDegree = 6.0;
    constexpr double GyroDeadZone = 1.5;
    constexpr double LookSens[] = { 1.0, 1.5, 2.0, 3.0, 4.0 };
    constexpr int LookSensCount = 5;

    enum class Kind { N64, Menu, Cheat, Camera, Level, Tray, Exit };
    enum class TrayItem { None, Gyro, Sens, Opacity, Controls, Camera, Selfies, Cheat, Level, Dpad };
    enum class Shot { None, Selfie, Cinematic, Action };
    enum class GyroMode { Off = 0, Touch = 1, Always = 2 };
    enum class Role { None, Stick, Look, Control };

    // The ten levels and the event that starts each (SotE-Recomp's
    // event_matches_level).
    struct Level {
        NSString *name;
        int event;
    };

    const Level Levels[] = {
        { @"Battle of Hoth", 3 },
        { @"Escape from Echo Base", 4 },
        { @"Asteroid Field", 6 },
        { @"Ord Mantell Junkyard", 7 },
        { @"Gall Spaceport", 11 },
        { @"Mos Eisley and Beggar's Canyon", 16 },
        { @"Imperial Freighter Suprosa", 18 },
        { @"Sewers of Imperial City", 24 },
        { @"Xizor's Palace", 26 },
        { @"Skyhook Battle", 28 },
    };

    struct Control {
        Kind kind;
        uint16_t bit;
        TrayItem tray;
        NSString *label;
        UIColor *accent;
        CGFloat radius;
        bool pill;
        CGPoint center;
        bool visible;
        CALayer *group;
        CAShapeLayer *shape;
        CATextLayer *text;
        CAShapeLayer *ring;
    };

    struct TouchState {
        Role role = Role::None;
        int control = -1;
        CGPoint start = CGPointZero;
        CGPoint last = CGPointZero;
        CFTimeInterval down = 0;
        bool moved = false;
        bool fired = false;
        bool burst = false;
        int burstShots = 0;
        CFTimeInterval nextBurst = 0;
        CGFloat swipeY = 0;
    };

    CGFloat distance(CGPoint a, CGPoint b) {
        return std::hypot(a.x - b.x, a.y - b.y);
    }

    UIColor *Gold() {
        return [UIColor colorWithRed:1.0 green:0.85 blue:0.3 alpha:0.95];
    }

    UIColor *RingBlue() {
        return [UIColor colorWithRed:0.47 green:0.78 blue:1.0 alpha:0.95];
    }

    UIColor *CheatRed() {
        return [UIColor colorWithRed:0.9 green:0.32 blue:0.28 alpha:1.0];
    }

    // Read by the gyro's queue.
    std::atomic<int> gyroMode{0};
    std::atomic<int> gyroSensIndex{1};
    std::atomic<bool> gyroThumbDown{false};
    std::atomic<bool> gyroSuppressed{false};
    std::atomic<int> gyroLandscapeSign{1};
}

@implementation SoteTouchControlsView {
    std::vector<Control> _controls;
    std::unordered_map<void *, TouchState> _touches;
    CADisplayLink *_displayLink;
    CMMotionManager *_motion;
    NSOperationQueue *_motionQueue;

    // Stick.
    UITouch *_stickTouch;
    CGPoint _stickHome;
    CGPoint _stickOrigin;
    CGPoint _stickKnob;
    CAShapeLayer *_stickBase;
    CAShapeLayer *_stickKnobLayer;

    // Tray, opacity row, toast, level card.
    bool _trayOpen;
    UIView *_trayBacking;
    UIView *_opacityRow;
    UISlider *_opacitySlider;
    UILabel *_toast;
    CFTimeInterval _toastUntil;
    UIView *_levelCard;
    UIView *_flash;

    // State.
    CFTimeInterval _startUntil;
    // Short presses queued by menu taps and swipes: bit, start, end.
    std::vector<std::tuple<uint16_t, CFTimeInterval, CFTimeInterval>> _pulses;
    CFTimeInterval _pulseCursor;
    // The stick was drawn under a thumb at the last refresh.
    bool _stickShown;
    // Look drag fractions not yet sent.
    double _lookCarryX;
    double _lookCarryY;
    // A tapped menu row: the setting to move to and confirm (-1 for none).
    int _menuTarget;
    int _menuDirection;
    int _menuLastFocus;
    int _menuSteps;
    uint16_t _pressed;
    CGFloat _opacity;
    bool _showCheat;
    bool _cheatOn;
    bool _showCamera;
    bool _showDpad;
    bool _classicControls;
    int _selfieIndex;
    Shot _shot;
    CFTimeInterval _shotStart;
    CFTimeInterval _shotNext;
    int _shotTaken;
    int _shotCount;
    bool _shotCaptureDue;
    float _pinchDistance;
    CGPoint _pinchMid;
    int _photosPending;
    int _photosToPhotos;
    int _photosToFiles;
}

#pragma mark - Setup

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self == nil) {
        return nil;
    }

    self.backgroundColor = UIColor.clearColor;
    self.multipleTouchEnabled = YES;
    [self loadSettings];
    _menuTarget = -1;

    UIColor *white = [UIColor colorWithWhite:1.0 alpha:0.4];
    UIColor *green = [UIColor colorWithRed:0.35 green:0.9 blue:0.45 alpha:0.6];
    UIColor *blue = [UIColor colorWithRed:0.45 green:0.65 blue:1.0 alpha:0.6];
    UIColor *yellow = [UIColor colorWithRed:1.0 green:0.85 blue:0.3 alpha:0.6];
    UIColor *red = [UIColor colorWithRed:1.0 green:0.45 blue:0.4 alpha:0.6];
    _controls = {
        { Kind::N64, N64A, TrayItem::None, @"A", green, 40, false },
        { Kind::N64, N64B, TrayItem::None, @"B", blue, 32, false },
        { Kind::N64, N64CUp, TrayItem::None, @"▲", yellow, 19, false },
        { Kind::N64, N64CDown, TrayItem::None, @"▼", yellow, 19, false },
        { Kind::N64, N64CLeft, TrayItem::None, @"◀", yellow, 19, false },
        { Kind::N64, N64CRight, TrayItem::None, @"▶", yellow, 19, false },
        { Kind::N64, N64Z, TrayItem::None, @"Z", white, 30, false },
        { Kind::N64, N64L, TrayItem::None, @"L", white, 22, true },
        { Kind::N64, N64R, TrayItem::None, @"R", white, 22, true },
        { Kind::N64, N64DUp, TrayItem::None, @"↑", white, 17, false },
        { Kind::N64, N64DDown, TrayItem::None, @"↓", white, 17, false },
        { Kind::N64, N64DLeft, TrayItem::None, @"←", white, 17, false },
        { Kind::N64, N64DRight, TrayItem::None, @"→", white, 17, false },
        { Kind::Menu, 0, TrayItem::None, @"START", red, 22, true },
        { Kind::Camera, 0, TrayItem::None, @"", white, 22, false },
        { Kind::Cheat, 0, TrayItem::None, @"", white, 22, false },
        { Kind::Tray, 0, TrayItem::Controls, @"", white, TrayRadius, true },
        { Kind::Tray, 0, TrayItem::Gyro, @"", white, TrayRadius, true },
        { Kind::Tray, 0, TrayItem::Sens, @"", white, TrayRadius, true },
        { Kind::Tray, 0, TrayItem::Opacity, @"", white, TrayRadius, true },
        { Kind::Tray, 0, TrayItem::Camera, @"", white, TrayRadius, true },
        { Kind::Tray, 0, TrayItem::Cheat, @"", white, TrayRadius, true },
        { Kind::Tray, 0, TrayItem::Level, @"", Gold(), TrayRadius, true },
        { Kind::Tray, 0, TrayItem::Dpad, @"", white, TrayRadius, true },
        { Kind::Tray, 0, TrayItem::Selfies, @"", white, TrayRadius, true },
        { Kind::Exit, 0, TrayItem::None, @"✕", white, 22, false },
    };

    _trayBacking = [[UIView alloc] init];
    _trayBacking.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.55];
    _trayBacking.layer.cornerRadius = 26;
    _trayBacking.layer.borderWidth = 1.5;
    _trayBacking.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.4].CGColor;
    _trayBacking.userInteractionEnabled = NO;
    _trayBacking.hidden = YES;
    [self addSubview:_trayBacking];

    _stickBase = [CAShapeLayer layer];
    _stickBase.fillColor = [UIColor colorWithWhite:0.0 alpha:0.22].CGColor;
    _stickBase.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.4].CGColor;
    _stickBase.lineWidth = 1.5;
    [self.layer addSublayer:_stickBase];
    _stickKnobLayer = [CAShapeLayer layer];
    _stickKnobLayer.fillColor = [UIColor colorWithWhite:1.0 alpha:0.30].CGColor;
    _stickKnobLayer.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.5].CGColor;
    _stickKnobLayer.lineWidth = 1.5;
    [self.layer addSublayer:_stickKnobLayer];

    for (Control &control : _controls) {
        [self buildControl:control];
    }

    [self buildOpacityRow];
    _toast = [[UILabel alloc] init];
    _toast.font = [UIFont boldSystemFontOfSize:14];
    _toast.textColor = UIColor.whiteColor;
    _toast.textAlignment = NSTextAlignmentCenter;
    _toast.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.6];
    _toast.layer.cornerRadius = 12;
    _toast.layer.masksToBounds = YES;
    _toast.hidden = YES;
    [self addSubview:_toast];

    _flash = [[UIView alloc] init];
    _flash.backgroundColor = UIColor.whiteColor;
    _flash.alpha = 0.0;
    _flash.userInteractionEnabled = NO;
    [self addSubview:_flash];

    __weak SoteTouchControlsView *weakSelf = self;
    sote_photos_install();
    sote_photos_set_saved_handler(^(BOOL toPhotos) {
        [weakSelf photoSaved:toPhotos];
    });
    if (_showCamera) {
        sote_photos_request_access();
    }

    sote_cheat_set(_cheatOn);
    [self startGyro];
    return self;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [_displayLink invalidate];
    _displayLink = nil;
    if (self.window != nil) {
        _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
        [_displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
}

- (void)loadSettings {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults registerDefaults:@{
        @"iosTouchGyroMode": @0,
        @"iosTouchGyroSens": @1,
        @"iosTouchOpacity": @1.0,
        @"iosTouchShowCheat": @NO,
        @"iosTouchCheatOn": @NO,
        @"iosTouchShowCamera": @YES,
        @"iosTouchShowDpad": @NO,
        @"iosTouchClassicControls": @NO,
        @"iosTouchSelfieShots": @1,
    }];
    gyroMode.store(int([defaults integerForKey:@"iosTouchGyroMode"]) % 3);
    gyroSensIndex.store(int([defaults integerForKey:@"iosTouchGyroSens"]) % LookSensCount);
    _opacity = std::clamp(CGFloat([defaults doubleForKey:@"iosTouchOpacity"]), CGFloat(0.2), CGFloat(1.0));
    _showCheat = [defaults boolForKey:@"iosTouchShowCheat"];
    _cheatOn = _showCheat && [defaults boolForKey:@"iosTouchCheatOn"];
    _showCamera = [defaults boolForKey:@"iosTouchShowCamera"];
    _showDpad = [defaults boolForKey:@"iosTouchShowDpad"];
    _classicControls = [defaults boolForKey:@"iosTouchClassicControls"];
    _selfieIndex = int([defaults integerForKey:@"iosTouchSelfieShots"]) % 3;
}

- (void)saveSettings {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setInteger:gyroMode.load() forKey:@"iosTouchGyroMode"];
    [defaults setInteger:gyroSensIndex.load() forKey:@"iosTouchGyroSens"];
    [defaults setDouble:_opacity forKey:@"iosTouchOpacity"];
    [defaults setBool:_showCheat forKey:@"iosTouchShowCheat"];
    [defaults setBool:_cheatOn forKey:@"iosTouchCheatOn"];
    [defaults setBool:_showCamera forKey:@"iosTouchShowCamera"];
    [defaults setBool:_showDpad forKey:@"iosTouchShowDpad"];
    [defaults setBool:_classicControls forKey:@"iosTouchClassicControls"];
    [defaults setInteger:_selfieIndex forKey:@"iosTouchSelfieShots"];
}

- (CATextLayer *)textLayer:(CGFloat)size {
    CATextLayer *text = [CATextLayer layer];
    text.fontSize = size;
    text.font = (__bridge CFTypeRef)[UIFont boldSystemFontOfSize:size].fontName;
    text.foregroundColor = [UIColor colorWithWhite:1.0 alpha:0.85].CGColor;
    text.alignmentMode = kCAAlignmentCenter;
    text.contentsScale = UIScreen.mainScreen.scale;
    return text;
}

- (void)buildControl:(Control &)control {
    control.group = [CALayer layer];
    control.shape = [CAShapeLayer layer];
    control.shape.lineWidth = 1.5;
    [control.group addSublayer:control.shape];
    const CGFloat size = (control.radius >= 30) ? 16 : (control.radius >= 20 ? 13 : 10);
    control.text = [self textLayer:(control.kind == Kind::Tray ? 10 : size)];
    control.text.string = control.label;
    [control.group addSublayer:control.text];
    control.ring = [CAShapeLayer layer];
    control.ring.fillColor = UIColor.clearColor.CGColor;
    control.ring.strokeColor = RingBlue().CGColor;
    control.ring.lineWidth = 3.0;
    control.ring.strokeEnd = 0.0;
    [control.group addSublayer:control.ring];
    [self.layer addSublayer:control.group];
}

- (void)buildOpacityRow {
    _opacityRow = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 300, 44)];
    _opacityRow.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.55];
    _opacityRow.layer.cornerRadius = 22;
    _opacityRow.hidden = YES;
    _opacitySlider = [[UISlider alloc] initWithFrame:CGRectMake(30, 0, 240, 44)];
    _opacitySlider.minimumValue = 0.2f;
    _opacitySlider.maximumValue = 1.0f;
    _opacitySlider.value = float(_opacity);
    _opacitySlider.minimumTrackTintColor = RingBlue();
    [_opacitySlider addTarget:self action:@selector(opacityChanged:) forControlEvents:UIControlEventValueChanged];
    [_opacitySlider addTarget:self action:@selector(opacityDone:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [_opacityRow addSubview:_opacitySlider];
    [self addSubview:_opacityRow];
}

#pragma mark - Layout

- (void)layoutSubviews {
    [super layoutSubviews];

    const UIEdgeInsets insets = self.safeAreaInsets;
    const CGFloat left = insets.left + 20;
    const CGFloat right = self.bounds.size.width - insets.right - 20;
    const CGFloat top = insets.top + 14;
    const CGFloat bottom = self.bounds.size.height - insets.bottom - 14;
    const CGFloat midX = CGRectGetMidX(self.bounds);

    const CGPoint a = CGPointMake(right - 48, bottom - 56);
    const CGPoint c = CGPointMake(right - 70, bottom - 196);
    const CGPoint dpad = CGPointMake(left + 156, top + 84);
    const CGFloat trayY = bottom - 74;
    int trayIndex = 0;
    int trayCount = 0;
    for (const Control &control : _controls) {
        trayCount += ((control.kind == Kind::Tray) && [self trayItemAvailable:control.tray]) ? 1 : 0;
    }

    for (Control &control : _controls) {
        switch (control.kind) {
            case Kind::N64:
                switch (control.bit) {
                    case N64A: control.center = a; break;
                    case N64B: control.center = CGPointMake(a.x - 82, a.y - 44); break;
                    case N64CUp: control.center = CGPointMake(c.x, c.y - 36); break;
                    case N64CDown: control.center = CGPointMake(c.x, c.y + 36); break;
                    case N64CLeft: control.center = CGPointMake(c.x - 36, c.y); break;
                    case N64CRight: control.center = CGPointMake(c.x + 36, c.y); break;
                    // Z sits under L like the N64's trigger, clear of the HUD's
                    // radar in the lower right.
                    case N64Z: control.center = CGPointMake(left + 44, top + 100); break;
                    case N64L: control.center = CGPointMake(left + 44, top + 30); break;
                    case N64R: control.center = CGPointMake(right - 44, top + 30); break;
                    case N64DUp: control.center = CGPointMake(dpad.x, dpad.y - 30); break;
                    case N64DDown: control.center = CGPointMake(dpad.x, dpad.y + 30); break;
                    case N64DLeft: control.center = CGPointMake(dpad.x - 30, dpad.y); break;
                    case N64DRight: control.center = CGPointMake(dpad.x + 30, dpad.y); break;
                    default: break;
                }
                break;
            case Kind::Menu: control.center = CGPointMake(midX, bottom - 16); break;
            // CHEAT and CAMERA sit either side of the top middle.
            case Kind::Cheat: control.center = CGPointMake(midX - 32, top + 30); break;
            case Kind::Camera: control.center = CGPointMake(midX + 32, top + 30); break;
            case Kind::Level: break;
            case Kind::Exit: control.center = CGPointMake(left + 44, top + 30); break;
            case Kind::Tray:
                if ([self trayItemAvailable:control.tray]) {
                    control.center = CGPointMake(midX + (trayIndex - (trayCount - 1) / 2.0) * TrayStep, trayY);
                    trayIndex++;
                }
                break;
        }

        [self shapeControl:control];
    }

    _trayBacking.frame = CGRectMake(midX - (trayCount * TrayStep) / 2.0 - 4, trayY - 26, trayCount * TrayStep + 8, 52);
    _opacityRow.center = CGPointMake(midX, trayY - 56);
    _toast.frame = CGRectMake(midX - 140, top + 50, 280, 30);
    _flash.frame = self.bounds;
    _stickHome = CGPointMake(left + 100, bottom - 96);
    if (_stickTouch == nil) {
        _stickOrigin = _stickHome;
        _stickKnob = _stickHome;
    }

    [self refresh];
}

- (CGRect)boundsForControl:(const Control &)control {
    const CGFloat r = control.radius;
    return control.pill ? CGRectMake(0, 0, r * 3.6, r * 1.6) : CGRectMake(0, 0, 2 * r, 2 * r);
}

- (void)shapeControl:(Control &)control {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    const CGRect bounds = [self boundsForControl:control];
    control.group.bounds = bounds;
    control.group.position = control.center;
    control.shape.path = (control.pill ?
        [UIBezierPath bezierPathWithRoundedRect:CGRectInset(bounds, 0.75, 0.75) cornerRadius:bounds.size.height / 2] :
        [UIBezierPath bezierPathWithOvalInRect:CGRectInset(bounds, 0.75, 0.75)]).CGPath;
    // The hold indicator fills the button's own border, starting at the top.
    if (control.pill) {
        const CGRect r = CGRectInset(bounds, 0.75, 0.75);
        const CGFloat radius = r.size.height / 2;
        UIBezierPath *border = [UIBezierPath bezierPath];
        [border moveToPoint:CGPointMake(CGRectGetMidX(r), CGRectGetMinY(r))];
        [border addLineToPoint:CGPointMake(CGRectGetMaxX(r) - radius, CGRectGetMinY(r))];
        [border addArcWithCenter:CGPointMake(CGRectGetMaxX(r) - radius, CGRectGetMidY(r)) radius:radius startAngle:-M_PI_2 endAngle:M_PI_2 clockwise:YES];
        [border addLineToPoint:CGPointMake(CGRectGetMinX(r) + radius, CGRectGetMaxY(r))];
        [border addArcWithCenter:CGPointMake(CGRectGetMinX(r) + radius, CGRectGetMidY(r)) radius:radius startAngle:M_PI_2 endAngle:3 * M_PI_2 clockwise:YES];
        [border closePath];
        control.ring.path = border.CGPath;
    }
    else {
        control.ring.path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds))
            radius:control.radius - 0.75 startAngle:-M_PI_2 endAngle:3 * M_PI_2 clockwise:YES].CGPath;
    }
    const CGFloat textHeight = control.text.fontSize * 1.25;
    control.text.frame = CGRectMake(0, (bounds.size.height - textHeight) / 2, bounds.size.width, textHeight);

    // Icons for the top-row extras.
    if ((control.kind == Kind::Camera) || (control.kind == Kind::Cheat)) {
        for (CALayer *sublayer in [control.group.sublayers copy]) {
            if ([sublayer.name isEqualToString:@"icon"]) {
                [sublayer removeFromSuperlayer];
            }
        }

        CAShapeLayer *icon = [CAShapeLayer layer];
        icon.name = @"icon";
        icon.frame = bounds;
        if (control.kind == Kind::Camera) {
            // SF Symbols are vector images; draw one into a bitmap for the layer.
            UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightSemibold];
            UIImage *symbol = [[UIImage systemImageNamed:@"camera.fill" withConfiguration:configuration]
                imageWithTintColor:[UIColor colorWithWhite:0.85 alpha:1.0] renderingMode:UIImageRenderingModeAlwaysOriginal];
            UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:symbol.size];
            UIImage *bitmap = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
                [symbol drawAtPoint:CGPointZero];
            }];
            CALayer *imageLayer = [CALayer layer];
            imageLayer.name = @"icon";
            imageLayer.frame = CGRectInset(bounds, bounds.size.width * 0.22, bounds.size.height * 0.22);
            imageLayer.contentsScale = UIScreen.mainScreen.scale;
            imageLayer.contents = (__bridge id)bitmap.CGImage;
            imageLayer.contentsGravity = kCAGravityResizeAspect;
            [control.group insertSublayer:imageLayer below:control.ring];
        }
        else {
            icon.path = [self imperialCrestInRect:CGRectInset(bounds, bounds.size.width * 0.18, bounds.size.height * 0.18)].CGPath;
            icon.fillColor = UIColor.clearColor.CGColor;
            icon.lineWidth = 1.6;
            [control.group insertSublayer:icon below:control.ring];
        }
    }

    [CATransaction commit];
}

// The Galactic Empire's crest, simplified: an outer ring, an inner hub and
// six spokes, drawn as strokes.
- (UIBezierPath *)imperialCrestInRect:(CGRect)rect {
    const CGPoint center = CGPointMake(CGRectGetMidX(rect), CGRectGetMidY(rect));
    const CGFloat outer = std::min(rect.size.width, rect.size.height) / 2;
    const CGFloat hub = outer * 0.36;
    UIBezierPath *path = [UIBezierPath bezierPathWithArcCenter:center radius:outer startAngle:0 endAngle:2 * M_PI clockwise:YES];
    [path moveToPoint:CGPointMake(center.x + hub, center.y)];
    [path addArcWithCenter:center radius:hub startAngle:0 endAngle:2 * M_PI clockwise:YES];
    for (int i = 0; i < 6; i++) {
        const CGFloat angle = M_PI / 6 + i * M_PI / 3;
        [path moveToPoint:CGPointMake(center.x + std::cos(angle) * hub, center.y + std::sin(angle) * hub)];
        [path addLineToPoint:CGPointMake(center.x + std::cos(angle) * outer, center.y + std::sin(angle) * outer)];
    }

    return path;
}

#pragma mark - Looks

- (bool)controlVisible:(const Control &)control {
    if (_shot != Shot::None) {
        // Selfies and the cinematic burst show nothing; Action Freeze keeps
        // only CAMERA (to shoot) and the exit button.
        return (_shot == Shot::Action) && ((control.kind == Kind::Camera) || (control.kind == Kind::Exit));
    }

    switch (control.kind) {
        case Kind::N64:
            if ((control.bit & (N64DUp | N64DDown | N64DLeft | N64DRight)) != 0) {
                return _showDpad;
            }

            return true;
        case Kind::Menu: return true;
        case Kind::Camera: return _showCamera;
        case Kind::Cheat: return _showCheat;
        case Kind::Level: return _showCheat && _cheatOn;
        case Kind::Tray: return _trayOpen && [self trayItemAvailable:control.tray];
        case Kind::Exit: return false;
    }

    return false;
}

// LEVEL is in the tray only while the cheat is on.
- (bool)trayItemAvailable:(TrayItem)item {
    return (item != TrayItem::Level) || (_showCheat && _cheatOn);
}

- (bool)trayItemOn:(TrayItem)item {
    switch (item) {
        case TrayItem::Gyro: return gyroMode.load() != int(GyroMode::Off);
        case TrayItem::Camera: return _showCamera;
        case TrayItem::Cheat: return _showCheat;
        case TrayItem::Dpad: return _showDpad;
        case TrayItem::Opacity: return !_opacityRow.hidden;
        default: return false;
    }
}

- (NSString *)trayLabel:(TrayItem)item {
    static NSString *const gyroNames[] = { @"GYRO\nOFF", @"GYRO\nTOUCH", @"GYRO\nON" };
    switch (item) {
        case TrayItem::Gyro:
            return (_motion.deviceMotionAvailable ? gyroNames[gyroMode.load()] : @"NO\nGYRO");
        case TrayItem::Sens: return [NSString stringWithFormat:@"SENS\n%.1fx", LookSens[gyroSensIndex.load()]];
        case TrayItem::Opacity: return [NSString stringWithFormat:@"OPACITY\n%d%%", int(std::lround(_opacity * 100))];
        case TrayItem::Controls: return _classicControls ? @"CONTROLS\nCLASSIC" : @"CONTROLS\nMODERN";
        case TrayItem::Camera: return _showCamera ? @"CAMERA\nON" : @"CAMERA\nOFF";
        case TrayItem::Cheat: return _showCheat ? @"CHEAT\nON" : @"CHEAT\nOFF";
        case TrayItem::Level: return @"LEVEL\nSELECT";
        case TrayItem::Dpad: return _showDpad ? @"D-PAD\nON" : @"D-PAD\nOFF";
        case TrayItem::Selfies: return [NSString stringWithFormat:@"SELFIES\n%d", SelfieCounts[_selfieIndex]];
        default: return @"";
    }
}

- (void)refresh {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (Control &control : _controls) {
        control.visible = [self controlVisible:control];
        control.group.hidden = !control.visible;
        if (!control.visible) {
            control.ring.strokeEnd = 0.0;
            continue;
        }

        const bool held = [self controlHeld:control];
        UIColor *border = control.accent;
        CGFloat fillWhite = held ? 0.30 : 0.0;
        CGFloat fillAlpha = held ? 0.30 : 0.22;
        if (control.kind == Kind::Tray) {
            control.text.string = [self trayLabel:control.tray];
            control.text.fontSize = 10;
            control.text.font = (__bridge CFTypeRef)[UIFont boldSystemFontOfSize:10].fontName;
            const CGRect trayBounds = [self boundsForControl:control];
            const bool twoLines = [(NSString *)control.text.string containsString:@"\n"];
            control.text.frame = CGRectMake(0, (trayBounds.size.height - (twoLines ? 26 : 13)) / 2, trayBounds.size.width, twoLines ? 26 : 14);
            control.text.wrapped = YES;
            control.group.opacity = 1.0;
            if ([self trayItemOn:control.tray] || (control.tray == TrayItem::Level)) {
                border = Gold();
            }
        }
        else {
            const CGFloat alpha = (held ? 1.0 : IdleAlpha) * _opacity;
            control.group.opacity = float(alpha);
        }

        if (control.kind == Kind::Cheat) {
            for (CALayer *sublayer in control.group.sublayers) {
                if ([sublayer.name isEqualToString:@"icon"] && [sublayer isKindOfClass:CAShapeLayer.class]) {
                    ((CAShapeLayer *)sublayer).strokeColor = (_cheatOn ? CheatRed() : [UIColor colorWithWhite:0.85 alpha:1.0]).CGColor;
                }
            }

            if (_cheatOn) {
                border = CheatRed();
            }

            control.group.shadowColor = CheatRed().CGColor;
            control.group.shadowRadius = 6;
            control.group.shadowOffset = CGSizeZero;
            control.group.shadowOpacity = _cheatOn ? 0.9f : 0.0f;
        }

        control.shape.fillColor = [UIColor colorWithWhite:fillWhite alpha:fillAlpha].CGColor;
        control.shape.strokeColor = border.CGColor;
        control.shape.lineWidth = ((control.kind == Kind::Cheat) && _cheatOn) ? 2.5 : 1.5;
    }

    _trayBacking.hidden = !_trayOpen;
    // Modern hides the stick until a thumb lands; Classic shows where it rests.
    const CGFloat stickAlpha = (_stickTouch != nil ? 1.0 : (_classicControls ? IdleAlpha : 0.0)) * _opacity;
    _stickShown = (_stickTouch != nil);
    _stickBase.opacity = float(stickAlpha);
    _stickKnobLayer.opacity = float(stickAlpha);
    _stickBase.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(_stickOrigin.x - StickRadius, _stickOrigin.y - StickRadius, 2 * StickRadius, 2 * StickRadius)].CGPath;
    _stickKnobLayer.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(_stickKnob.x - StickKnob, _stickKnob.y - StickKnob, 2 * StickKnob, 2 * StickKnob)].CGPath;
    [CATransaction commit];
}

- (bool)controlHeld:(const Control &)control {
    const int index = int(&control - _controls.data());
    for (const auto &entry : _touches) {
        if ((entry.second.role == Role::Control) && (entry.second.control == index)) {
            return true;
        }
    }

    return (control.kind == Kind::N64) && ((_pressed & control.bit) != 0);
}

#pragma mark - Touches

// The visible control nearest a point, within its size plus the slop.
- (int)controlAt:(CGPoint)point {
    int best = -1;
    CGFloat bestDistance = CGFLOAT_MAX;
    for (size_t i = 0; i < _controls.size(); i++) {
        const Control &control = _controls[i];
        if (!control.visible) {
            continue;
        }

        const CGRect bounds = CGRectInset([self boundsForControl:control], -TouchSlop, -TouchSlop);
        const CGRect frame = CGRectOffset(bounds, control.center.x - CGRectGetMidX(bounds) + 0, control.center.y - CGRectGetMidY(bounds));
        const CGFloat d = distance(point, control.center);
        const bool inside = control.pill ? CGRectContainsPoint(frame, point) : (d <= control.radius + TouchSlop);
        if (inside && (d < bestDistance)) {
            best = int(i);
            bestDistance = d;
        }
    }

    return best;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    const CFTimeInterval now = CACurrentMediaTime();
    for (UITouch *touch in touches) {
        const CGPoint p = [touch locationInView:self];
        if (_levelCard != nil) {
            continue;
        }

        TouchState state;
        state.start = p;
        state.last = p;
        state.down = now;
        const int index = [self controlAt:p];
        if (index >= 0) {
            state.role = Role::Control;
            state.control = index;
        }
        else if (_trayOpen) {
            // A touch anywhere else closes the tray.
            [self closeTray];
            continue;
        }
        else if ((_stickTouch == nil) && (_shot == Shot::None) && (p.x < self.bounds.size.width * StickAreaFraction) && (p.y > self.safeAreaInsets.top + 130)) {
            state.role = Role::Stick;
            _stickTouch = touch;
            _stickOrigin = p;
            _stickKnob = p;
        }
        else {
            state.role = Role::Look;
        }

        _touches[(__bridge void *)touch] = state;
    }

    [self updateInput];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    for (UITouch *touch in touches) {
        auto it = _touches.find((__bridge void *)touch);
        if (it == _touches.end()) {
            continue;
        }

        TouchState &state = it->second;
        const CGPoint p = [touch locationInView:self];
        if (state.role == Role::Look) {
            const CGFloat dx = p.x - state.last.x;
            const CGFloat dy = p.y - state.last.y;
            if (distance(p, state.start) > HoldMoveLimit) {
                state.moved = true;
            }

            if (_shot == Shot::Action) {
                [self orbitWithTouch:touch delta:CGPointMake(dx, dy)];
            }
            else if ([self menuShowing]) {
                // In the game's menus a swipe moves the selection, one row
                // per MenuSwipeStep points.
                state.swipeY += dy;
                while (state.swipeY <= -MenuSwipeStep) {
                    [self pulse:N64DUp];
                    state.swipeY += MenuSwipeStep;
                }

                while (state.swipeY >= MenuSwipeStep) {
                    [self pulse:N64DDown];
                    state.swipeY -= MenuSwipeStep;
                }
            }
            else {
                // Keep the fractions, so slow drags still turn.
                const double sens = LookSens[gyroSensIndex.load()];
                _lookCarryX += dx * LookCountsPerPoint * sens;
                _lookCarryY += dy * LookCountsPerPoint * sens;
                const int countsX = int(_lookCarryX);
                const int countsY = int(_lookCarryY);
                _lookCarryX -= countsX;
                _lookCarryY -= countsY;
                if ((countsX != 0) || (countsY != 0)) {
                    sote::platform::ios_add_look(countsX, countsY);
                }
            }
        }
        else if (state.role == Role::Control) {
            const Control &control = _controls[state.control];
            const CGFloat dx = p.x - state.start.x;
            if (distance(p, state.start) > HoldMoveLimit) {
                state.moved = true;
            }

            // CAMERA: a sideways slide starts a burst for as long as the
            // finger stays down; up starts the cinematic burst, down Action
            // Freeze.
            const CGFloat dyStart = p.y - state.start.y;
            if ((control.kind == Kind::Camera) && (_shot == Shot::None) && !state.burst && !state.fired) {
                if ((std::fabs(dx) >= BurstSlide) && (std::fabs(dx) > std::fabs(dyStart))) {
                    state.burst = true;
                    state.moved = true;
                    state.nextBurst = 0;
                }
                else if (dyStart <= -CameraSwipe) {
                    state.fired = true;
                    [self startShot:Shot::Cinematic];
                }
                else if (dyStart >= CameraSwipe) {
                    state.fired = true;
                    [self startShot:Shot::Action];
                }
            }
        }

        state.last = p;
    }

    [self updateInput];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    for (UITouch *touch in touches) {
        auto it = _touches.find((__bridge void *)touch);
        if (it == _touches.end()) {
            continue;
        }

        const TouchState state = it->second;
        _touches.erase(it);
        if (touch == _stickTouch) {
            _stickTouch = nil;
        }

        if ((state.role == Role::Control) && !state.fired && !state.moved && (event != nil)) {
            [self tapControl:state.control];
        }
        else if ((state.role == Role::Look) && !state.moved && (event != nil) &&
                 (CACurrentMediaTime() - state.down < MenuTapTime)) {
            if ([self menuShowing]) {
                // A tap on a row of the pause or options menu picks it; on
                // other menus a tap confirms, like A.
                const int row = [self menuRowAt:state.last];
                if (row >= 0) {
                    [self chooseMenuRow:row];
                }
                else if (row == -1) {
                    [self pulse:N64A];
                }
            }
            else if ([self tapOnMessage:state.last]) {
                // A tap clears a message box, like Start.
                [self pulse:N64Start];
            }
        }
        else if ((state.role == Role::Control) && state.burst) {
            [self finishBurst];
        }
    }

    [self updateInput];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self touchesEnded:touches withEvent:nil];
}

#pragma mark - Actions

// True while one of the game's menus (pause, options, profiles...) is up.
- (bool)menuShowing {
    return sote::menu_skin::latest() != nullptr;
}

// A tap on a message box the game is showing: within the 4:3 picture, from
// a little above its first line to a few lines below it (N64 pixels, 240
// to the screen's height). Taps elsewhere, on the HUD or radar, are not.
- (bool)tapOnMessage:(CGPoint)p {
    int top = 0;
    if (!sote::platform::ios_message_showing(&top)) {
        return false;
    }

    const CGFloat height = self.bounds.size.height;
    const CGFloat y = p.y / height * 240.0;
    const bool inPicture = std::fabs(p.x - self.bounds.size.width / 2.0) < height * 2.0 / 3.0;
    return inPicture && (y >= top - 16) && (y <= top + 64);
}

// The game's menus are drawn on a 960 x 540 canvas, fitted to the screen's
// height and centred (SotE-Recomp's menu_canvas.cpp).
- (CGPoint)menuCanvasPoint:(CGPoint)p {
    const CGFloat scale = self.bounds.size.height / 540.0;
    return CGPointMake((p.x - self.bounds.size.width / 2.0) / scale + 480.0, p.y / scale);
}

static bool menuRowSelected(const sote::menu_skin::Row &row) {
    return ((row.color >> 24) & 255) >= 0xA0 && ((row.color >> 16) & 255) >= 0xD0 && ((row.color >> 8) & 255) >= 0xA0;
}

// The setting of the pause or options menu under a point, which the game
// reports as focused_setting when it is selected: >= 0 for a row, -2 for a
// point off the rows of those menus, -1 for any other menu.
- (int)menuRowAt:(CGPoint)point {
    const auto snapshot = sote::menu_skin::latest();
    if (snapshot == nullptr) {
        return -1;
    }

    const CGPoint c = [self menuCanvasPoint:point];
    if (snapshot->screen == sote::menu_skin::Screen::Pause) {
        // Resume, Options, Quit: 43 apart from y 216, in a box 264-696 wide.
        if ((c.x < 264) || (c.x > 696) || (c.y < 207) || (c.y > 352)) {
            return -2;
        }

        return std::clamp(int((c.y - 214.0) / 43.0), 0, 2);
    }

    if (snapshot->screen == sote::menu_skin::Screen::Options) {
        // The return row at the bottom, then the settings, 40 apart from
        // y 123, each setting (row - 51) / 2.
        if ((c.x >= 254) && (c.x <= 706) && (c.y >= 503) && (c.y <= 542)) {
            return 0;
        }

        if ((c.x < 184) || (c.x > 849)) {
            return -2;
        }

        int index = 0;
        for (int row = 53; row <= 67; row += 2) {
            if (!snapshot->rows[row].visible()) {
                continue;
            }

            const CGFloat y = 126.0 + index * 40;
            if (y > 447) {
                break;
            }

            if ((c.y >= y - 4) && (c.y < y + 36)) {
                return (row - 51) / 2;
            }

            index++;
        }

        return -2;
    }

    return -1;
}

// The setting the pause or options menu has selected, or -1.
- (int)menuFocus {
    const auto snapshot = sote::menu_skin::latest();
    if (snapshot == nullptr) {
        return -1;
    }

    if (snapshot->focused_setting >= 0) {
        return snapshot->focused_setting;
    }

    if (snapshot->screen == sote::menu_skin::Screen::Options) {
        if (menuRowSelected(snapshot->rows[52])) {
            return 0;
        }

        for (int row = 53; row <= 67; row += 2) {
            if (snapshot->rows[row].visible() && menuRowSelected(snapshot->rows[row])) {
                return (row - 51) / 2;
            }
        }
    }

    return -1;
}

// Moves the menu's selection to a tapped row with D-pad presses, watching
// the game's own selection, then confirms with A.
- (void)chooseMenuRow:(int)row {
    const int focus = [self menuFocus];
    if (focus < 0) {
        [self pulse:N64A];
        return;
    }

    _menuTarget = row;
    _menuSteps = 0;
    _menuLastFocus = -1;
    // The options menu's return row (0) sits below the settings.
    _menuDirection = ((row == 0) && (sote::menu_skin::latest() != nullptr) &&
        (sote::menu_skin::latest()->screen == sote::menu_skin::Screen::Options)) ? 1 : ((row > focus) ? 1 : -1);
}

- (void)tickMenuTap:(CFTimeInterval)now {
    if (_menuTarget < 0) {
        return;
    }

    // Let the last press land and the menu redraw before looking again.
    if (!_pulses.empty() || (now < _pulseCursor + 0.08)) {
        return;
    }

    const int focus = [self menuFocus];
    if ((focus < 0) || (_menuSteps > 12)) {
        _menuTarget = -1;
        return;
    }

    if (focus == _menuTarget) {
        _menuTarget = -1;
        [self pulse:N64A];
        return;
    }

    // At an end that does not wrap, turn round.
    if (focus == _menuLastFocus) {
        _menuDirection = -_menuDirection;
    }

    _menuLastFocus = focus;
    _menuSteps++;
    [self pulse:(_menuDirection > 0) ? N64DDown : N64DUp];
}

// Queues a short press of an N64 button, after any already queued, so
// repeated presses are seen as separate.
- (void)pulse:(uint16_t)bit {
    const CFTimeInterval start = std::max(CACurrentMediaTime(), _pulseCursor);
    _pulses.emplace_back(bit, start, start + MenuPulse);
    _pulseCursor = start + MenuPulse + MenuPulseGap;
}

- (void)tapControl:(int)index {
    Control &control = _controls[index];
    switch (control.kind) {
        case Kind::Menu:
            _startUntil = CACurrentMediaTime() + StartPulse;
            break;
        case Kind::Camera:
            [self takePhotos:1];
            break;
        case Kind::Exit:
            [self endShot];
            break;
        case Kind::Tray:
            [self useTray:control.tray];
            break;
        default:
            break;
    }
}

// Holds that complete while the finger is still down.
- (void)holdControl:(int)index {
    Control &control = _controls[index];
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    switch (control.kind) {
        case Kind::Menu:
            [haptic impactOccurred];
            _trayOpen ? [self closeTray] : [self openTray];
            break;
        case Kind::Cheat:
            [haptic impactOccurred];
            [self setCheat:!_cheatOn];
            break;
        case Kind::Camera:
            if (_shot == Shot::None) {
                [haptic impactOccurred];
                [self startShot:Shot::Selfie];
            }
            break;
        case Kind::Tray:
            if (control.tray == TrayItem::Opacity) {
                [haptic impactOccurred];
                _opacity = 1.0;
                _opacitySlider.value = 1.0f;
                [self saveSettings];
                [self showToast:@"Opacity 100%"];
            }
            break;
        default:
            break;
    }
}

- (double)holdTimeFor:(const Control &)control {
    switch (control.kind) {
        case Kind::Menu: return MenuHold;
        case Kind::Cheat: return CheatHold;
        case Kind::Camera: return (_shot == Shot::None) ? CameraHold : 0.0;
        case Kind::Tray: return (control.tray == TrayItem::Opacity) ? MenuHold : 0.0;
        default: return 0.0;
    }
}

- (void)openTray {
    _trayOpen = YES;
    gyroSuppressed.store(true);
    [self refresh];
}

- (void)closeTray {
    _trayOpen = NO;
    _opacityRow.hidden = YES;
    gyroSuppressed.store(_levelCard != nil);
    [self refresh];
}

- (void)useTray:(TrayItem)item {
    switch (item) {
        case TrayItem::Gyro:
            if (_motion.deviceMotionAvailable) {
                gyroMode.store((gyroMode.load() + 1) % 3);
            }
            break;
        case TrayItem::Sens:
            gyroSensIndex.store((gyroSensIndex.load() + 1) % LookSensCount);
            break;
        case TrayItem::Opacity:
            _opacityRow.hidden = !_opacityRow.hidden;
            break;
        case TrayItem::Camera:
            _showCamera = !_showCamera;
            if (_showCamera) {
                sote_photos_request_access();
            }
            break;
        case TrayItem::Cheat:
            _showCheat = !_showCheat;
            [self setCheat:_showCheat];
            break;
        case TrayItem::Dpad:
            _showDpad = !_showDpad;
            break;
        case TrayItem::Controls:
            _classicControls = !_classicControls;
            [self applyControlScheme];
            [self showToast:_classicControls ? @"Classic controls (the N64's own)" : @"Modern controls: move and strafe, drag to look"];
            break;
        case TrayItem::Level:
            [self openLevelCard];
            break;
        case TrayItem::Selfies:
            _selfieIndex = (_selfieIndex + 1) % 3;
            break;
        default:
            break;
    }

    [self saveSettings];
    [self refresh];
}

// SotE-Recomp's on-foot scheme: Modern (move and strafe, look separately)
// or Classic (the N64's turn-and-walk), switched live and saved to
// sote_controls.json.
- (void)applyControlScheme {
    using namespace sote::controls_menu;
    const ControlScheme wanted = _classicControls ? ControlScheme::Classic : ControlScheme::Modern;
    if (current_scheme(SchemeSlot::OnFoot) != wanted) {
        cycle_scheme(SchemeSlot::OnFoot, 1);
        persist();
    }
}

- (void)opacityChanged:(UISlider *)slider {
    _opacity = std::round(slider.value * 20.0f) / 20.0f;
    [self refresh];
}

- (void)opacityDone:(UISlider *)slider {
    [self saveSettings];
}

- (void)setCheat:(bool)on {
    const bool wasOn = _cheatOn;
    _cheatOn = on;
    sote_cheat_set(on);
    [self saveSettings];
    [self setNeedsLayout];
    if (on && !wasOn) {
        sote_cheat_play_sound();
    }

    [self refresh];
}

- (void)showToast:(NSString *)text {
    _toast.text = text;
    const CGFloat width = std::min(self.bounds.size.width - 40, [text sizeWithAttributes:@{ NSFontAttributeName: _toast.font }].width + 32);
    _toast.frame = CGRectMake(CGRectGetMidX(self.bounds) - width / 2, _toast.frame.origin.y, width, 30);
    _toast.hidden = NO;
    _toastUntil = CACurrentMediaTime() + ToastTime;
}

#pragma mark - Camera

- (void)takePhotos:(int)count {
    for (int i = 0; i < count; i++) {
        sote_photos_capture();
    }

    _photosPending += count;
    [self cameraFeedback:(count == 1) burst:NO];
}

- (void)cameraFeedback:(bool)full burst:(bool)burst {
    _flash.alpha = burst ? 0.35 : 0.85;
    [UIView animateWithDuration:(burst ? 0.12 : 0.3) animations:^{
        self->_flash.alpha = 0.0;
    }];
    AudioServicesPlaySystemSound(burst ? 1104 : 1108);
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
}

- (void)finishBurst {}

- (void)photoSaved:(BOOL)toPhotos {
    if (toPhotos) {
        _photosToPhotos++;
    }
    else {
        _photosToFiles++;
    }

    _photosPending = std::max(0, _photosPending - 1);
    if (_photosPending == 0) {
        if (_photosToFiles > 0) {
            [self showToast:[NSString stringWithFormat:@"%d saved to Files (Screenshots)", _photosToFiles + _photosToPhotos]];
        }
        else {
            [self showToast:(_photosToPhotos == 1) ? @"Photo saved" : [NSString stringWithFormat:@"%d photos saved", _photosToPhotos]];
        }

        _photosToPhotos = 0;
        _photosToFiles = 0;
    }
}

#pragma mark - Freeze camera and selfies

// Holds the game and asks RT64 to keep showing its last frame from an orbit
// around Dash. Selfie: the camera swings round in front of him for 1, 3 or 5
// shots. Cinematic: 5 shots sweeping round the frozen moment. Action Freeze:
// drag to orbit, pinch to zoom, two fingers to pan, CAMERA to shoot, ✕ to
// leave.
- (void)startShot:(Shot)shot {
    [self closeTray];
    float x = 0.0f;
    float y = 0.0f;
    float z = 0.0f;
    const bool havePivot = sote::platform::ios_player_position(&x, &y, &z);
    RT64::iosFreezePivot[0].store(x);
    RT64::iosFreezePivot[1].store(y);
    RT64::iosFreezePivot[2].store(z);
    RT64::iosFreezeHasPivot.store(havePivot);
    float eye[3] = {};
    float forward[3] = {};
    const bool haveEye = sote::platform::ios_game_camera(eye, forward);
    for (int i = 0; i < 3; i++) {
        RT64::iosFreezeEye[i].store(eye[i]);
        RT64::iosFreezeForward[i].store(forward[i]);
    }

    RT64::iosFreezeHasEye.store(haveEye);
    [self setOrbitYaw:0.0f pitch:0.0f zoom:1.0f];
    RT64::iosFreezePanX.store(0.0f);
    RT64::iosFreezePanY.store(0.0f);
    sote::platform::ios_set_game_held(true);
    RT64::iosFreezeRequested.store(true);
    gyroSuppressed.store(true);
    _shot = shot;
    _shotStart = CACurrentMediaTime();
    _shotNext = _shotStart + FreezeSettle;
    _shotTaken = 0;
    _shotCaptureDue = false;
    _shotCount = (shot == Shot::Selfie) ? SelfieCounts[_selfieIndex] : ((shot == Shot::Cinematic) ? 5 : 0);
    _pinchDistance = 0.0f;
    [self refresh];
}

- (void)endShot {
    RT64::iosFreezeRequested.store(false);
    sote::platform::ios_set_game_held(false);
    gyroSuppressed.store(_trayOpen || (_levelCard != nil));
    _shot = Shot::None;
    [self refresh];
}

- (void)setOrbitYaw:(float)yaw pitch:(float)pitch zoom:(float)zoom {
    RT64::iosFreezeYaw.store(yaw);
    RT64::iosFreezePitch.store(pitch);
    RT64::iosFreezeZoom.store(zoom);
}

static float randomBetween(float low, float high) {
    return low + (high - low) * float(arc4random_uniform(10001)) / 10000.0f;
}

- (void)tickShot:(CFTimeInterval)now {
    if (_shot == Shot::None) {
        return;
    }

    if (!RT64::iosFreezeActive.load()) {
        if (now - _shotStart > FreezeTimeout) {
            // No 3D view to orbit here (a menu or a story screen).
            [self endShot];
            [self showToast:@"No camera here"];
        }

        return;
    }

    if ((_shot == Shot::Action) || (now < _shotNext)) {
        return;
    }

    if (_shotCaptureDue) {
        // The camera has had a moment to settle: take the shot.
        _shotCaptureDue = false;
        [self takePhotos:1];
        _shotTaken++;
        _shotNext = now + ((_shotTaken < _shotCount) ? ShotGap : ShotShow);
        return;
    }

    if (_shotTaken >= _shotCount) {
        [self endShot];
        return;
    }

    if (_shot == Shot::Selfie) {
        // In front of Dash, a little above, at arm's length, a fresh angle
        // for each shot.
        // Three-quarters on and looking a little down, rather than straight
        // at his face: the game only drew what its own camera could see, so
        // a view straight back towards it can be empty sky.
        const float side = (arc4random_uniform(2) == 0) ? -1.0f : 1.0f;
        [self setOrbitYaw:float(M_PI) + side * randomBetween(0.45f, 0.85f) pitch:randomBetween(0.15f, 0.4f) zoom:randomBetween(0.4f, 0.6f)];
    }
    else {
        // Sweep round the frozen moment.
        const float t = (_shotCount > 1) ? float(_shotTaken) / float(_shotCount - 1) : 0.5f;
        [self setOrbitYaw:-1.0f + 2.0f * t pitch:0.15f zoom:0.85f];
    }

    _shotCaptureDue = true;
    _shotNext = now + ShotSettle;
}

// Action Freeze: one finger orbits, two pinch to zoom and pan.
- (void)orbitWithTouch:(UITouch *)touch delta:(CGPoint)delta {
    std::vector<CGPoint> points;
    for (const auto &entry : _touches) {
        if (entry.second.role == Role::Look) {
            points.push_back(entry.second.last);
        }
    }

    if (points.size() >= 2) {
        const CGPoint a = (touch == nil) ? points[0] : [touch locationInView:self];
        CGPoint b = points[0];
        for (const CGPoint &point : points) {
            if (distance(point, a) > distance(b, a)) {
                b = point;
            }
        }

        const float spread = float(distance(a, b));
        const CGPoint mid = CGPointMake((a.x + b.x) / 2, (a.y + b.y) / 2);
        if ((_pinchDistance > 0.0f) && (spread > 1.0f)) {
            RT64::iosFreezeZoom.store(std::clamp(RT64::iosFreezeZoom.load() * (_pinchDistance / spread), 0.15f, 4.0f));
            RT64::iosFreezePanX.store(RT64::iosFreezePanX.load() - float((mid.x - _pinchMid.x) / self.bounds.size.width));
            RT64::iosFreezePanY.store(RT64::iosFreezePanY.load() + float((mid.y - _pinchMid.y) / self.bounds.size.height));
        }

        _pinchDistance = spread;
        _pinchMid = mid;
        return;
    }

    _pinchDistance = 0.0f;
    RT64::iosFreezeYaw.store(RT64::iosFreezeYaw.load() - float(delta.x) * OrbitRadiansPerPoint);
    RT64::iosFreezePitch.store(std::clamp(RT64::iosFreezePitch.load() + float(delta.y) * OrbitRadiansPerPoint, -1.4f, 1.4f));
}

#pragma mark - Level selector

- (void)openLevelCard {
    [self closeTray];
    gyroSuppressed.store(true);
    UIView *dim = [[UIView alloc] initWithFrame:self.bounds];
    dim.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.45];
    UIView *card = [[UIView alloc] init];
    card.backgroundColor = [UIColor colorWithWhite:0.06 alpha:0.92];
    card.layer.cornerRadius = 16;
    card.layer.borderWidth = 1.5;
    card.layer.borderColor = [UIColor colorWithRed:1.0 green:0.85 blue:0.3 alpha:0.7].CGColor;
    const CGFloat width = std::min(CGFloat(440), self.bounds.size.width - 40);
    const CGFloat rowHeight = 30;
    const NSUInteger count = sizeof(Levels) / sizeof(Levels[0]);
    const CGFloat height = 48 + rowHeight * ((count + 1) / 2) + 12;
    card.frame = CGRectMake((self.bounds.size.width - width) / 2, (self.bounds.size.height - height) / 2, width, height);
    [dim addSubview:card];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16, 10, width - 60, 28)];
    title.text = @"LEVEL";
    title.textColor = Gold();
    title.font = [UIFont fontWithName:@"AvenirNextCondensed-Bold" size:17] ?: [UIFont boldSystemFontOfSize:17];
    [card addSubview:title];
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(width - 42, 8, 30, 30);
    [close setTitle:@"✕" forState:UIControlStateNormal];
    [close setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [close addTarget:self action:@selector(closeLevelCard) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:close];

    for (NSUInteger i = 0; i < count; i++) {
        UIButton *row = [UIButton buttonWithType:UIButtonTypeSystem];
        const CGFloat columnWidth = (width - 24) / 2;
        row.frame = CGRectMake(12 + (i % 2) * columnWidth, 44 + (i / 2) * rowHeight, columnWidth, rowHeight);
        row.tag = NSInteger(i);
        row.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"%lu  ", (unsigned long)(i + 1)]
            attributes:@{ NSForegroundColorAttributeName: Gold(), NSFontAttributeName: [UIFont boldSystemFontOfSize:14] }];
        [text appendAttributedString:[[NSAttributedString alloc] initWithString:Levels[i].name
            attributes:@{ NSForegroundColorAttributeName: UIColor.whiteColor, NSFontAttributeName: [UIFont systemFontOfSize:14] }]];
        [row setAttributedTitle:text forState:UIControlStateNormal];
        [row addTarget:self action:@selector(levelChosen:) forControlEvents:UIControlEventTouchUpInside];
        [card addSubview:row];
    }

    _levelCard = dim;
    [self addSubview:dim];
}

- (void)closeLevelCard {
    [_levelCard removeFromSuperview];
    _levelCard = nil;
    gyroSuppressed.store(_trayOpen);
}

- (void)levelChosen:(UIButton *)row {
    const Level &level = Levels[row.tag];
    sote::platform::ios_request_level_jump(level.event);
    [self closeLevelCard];
    [self showToast:[NSString stringWithFormat:@"Loading %@", level.name]];
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    // The level card and opacity slider are real controls; everything else is
    // handled by this view's own touch tracking.
    if (_levelCard != nil) {
        return [_levelCard hitTest:[self convertPoint:point toView:_levelCard] withEvent:event] ?: _levelCard;
    }

    if (!_opacityRow.hidden && CGRectContainsPoint(_opacityRow.frame, point)) {
        return [_opacityRow hitTest:[self convertPoint:point toView:_opacityRow] withEvent:event];
    }

    return [super hitTest:point withEvent:event] != nil ? self : nil;
}

#pragma mark - Every frame

- (void)tick:(CADisplayLink *)link {
    const CFTimeInterval now = CACurrentMediaTime();
    bool changed = false;
    [self tickShot:now];
    [self tickMenuTap:now];
    for (auto &entry : _touches) {
        TouchState &state = entry.second;
        if (state.role != Role::Control) {
            continue;
        }

        Control &control = _controls[state.control];
        if ((control.kind == Kind::Camera) && state.burst) {
            if ((state.burstShots < BurstMax) && (now >= state.nextBurst)) {
                sote_photos_capture();
                _photosPending++;
                state.burstShots++;
                state.nextBurst = now + BurstPeriod;
                [self cameraFeedback:false burst:true];
                [self showToast:[NSString stringWithFormat:@"%d", state.burstShots]];
            }

            continue;
        }

        const double hold = [self holdTimeFor:control];
        if ((hold <= 0.0) || state.fired) {
            continue;
        }

        if (state.moved) {
            control.ring.strokeEnd = 0.0;
            continue;
        }

        const double progress = (now - state.down) / hold;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        control.ring.strokeEnd = std::min(1.0, progress);
        [CATransaction commit];
        if (progress >= 1.0) {
            state.fired = true;
            control.ring.strokeEnd = 0.0;
            [self holdControl:state.control];
            changed = true;
        }
    }

    for (Control &control : _controls) {
        bool holding = false;
        for (const auto &entry : _touches) {
            holding = holding || ((entry.second.role == Role::Control) && (&_controls[entry.second.control] == &control) && !entry.second.fired && !entry.second.moved);
        }

        if (!holding && (control.ring.strokeEnd != 0.0)) {
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            control.ring.strokeEnd = 0.0;
            [CATransaction commit];
        }
    }

    if (!_toast.hidden && (now > _toastUntil)) {
        _toast.hidden = YES;
    }

    [self updateInput];
    if (changed) {
        [self refresh];
    }
}

- (void)updateInput {
    uint16_t bits = 0;
    bool thumb = (_stickTouch != nil);
    for (const auto &entry : _touches) {
        const TouchState &state = entry.second;
        if (state.role == Role::Look) {
            thumb = true;
        }
        else if ((state.role == Role::Control) && (_controls[state.control].kind == Kind::N64)) {
            // N64 buttons follow the finger, so a thumb can roll between them.
            const int index = [self controlAt:state.last];
            if ((index >= 0) && (_controls[index].kind == Kind::N64)) {
                bits |= _controls[index].bit;
            }

            thumb = true;
        }
    }

    const CFTimeInterval now = CACurrentMediaTime();
    if (now < _startUntil) {
        bits |= N64Start;
    }

    for (auto it = _pulses.begin(); it != _pulses.end();) {
        if (now >= std::get<2>(*it)) {
            it = _pulses.erase(it);
            continue;
        }

        if (now >= std::get<1>(*it)) {
            bits |= std::get<0>(*it);
        }

        ++it;
    }

    float x = 0.0f;
    float y = 0.0f;
    if (_stickTouch != nil) {
        auto it = _touches.find((__bridge void *)_stickTouch);
        const CGPoint p = (it != _touches.end()) ? it->second.last : _stickOrigin;
        CGFloat dx = p.x - _stickOrigin.x;
        CGFloat dy = p.y - _stickOrigin.y;
        const CGFloat length = std::hypot(dx, dy);
        if (length > StickRadius) {
            dx *= StickRadius / length;
            dy *= StickRadius / length;
        }

        _stickKnob = CGPointMake(_stickOrigin.x + dx, _stickOrigin.y + dy);
        if (std::hypot(dx, dy) / StickRadius > StickDeadZone) {
            x = float(dx / StickRadius);
            y = float(-dy / StickRadius);
        }
    }
    else {
        _stickOrigin = _stickHome;
        _stickKnob = _stickHome;
    }

    gyroThumbDown.store(thumb);
    const bool changed = (bits != _pressed);
    _pressed = bits;
    if (_shot != Shot::None) {
        bits = 0;
        x = 0.0f;
        y = 0.0f;
    }

    sote::platform::ios_set_touch_input(bits, x, y);
    // Redraw while the stick is held, and once more when it is let go, so
    // it disappears with the thumb.
    if (changed || (_stickTouch != nil) || _stickShown) {
        [self refresh];
    }
}

#pragma mark - Gyro

- (void)startGyro {
    _motion = [[CMMotionManager alloc] init];
    if (!_motion.deviceMotionAvailable) {
        return;
    }

    _motionQueue = [[NSOperationQueue alloc] init];
    _motionQueue.maxConcurrentOperationCount = 1;
    _motion.deviceMotionUpdateInterval = 0.01;
    [self updateLandscapeSign];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateLandscapeSign)
        name:UIDeviceOrientationDidChangeNotification object:nil];

    __block CFTimeInterval lastTime = 0;
    __block double carryX = 0.0;
    __block double carryY = 0.0;
    __block CFTimeInterval quietUntil = 0;
    __block int lastSign = gyroLandscapeSign.load();
    [_motion startDeviceMotionUpdatesUsingReferenceFrame:CMAttitudeReferenceFrameXArbitraryZVertical
        toQueue:_motionQueue withHandler:^(CMDeviceMotion *motion, NSError *error) {
        if (motion == nil) {
            return;
        }

        const CFTimeInterval now = motion.timestamp;
        const double dt = (lastTime > 0) ? (now - lastTime) : 0.0;
        lastTime = now;
        const int sign = gyroLandscapeSign.load();
        if (sign != lastSign) {
            // No aiming for a moment after the screen flips sides.
            lastSign = sign;
            quietUntil = now + 0.35;
        }

        const GyroMode mode = GyroMode(gyroMode.load());
        if ((mode == GyroMode::Off) || gyroSuppressed.load() || (dt <= 0.0) || (dt > 0.5) || (now < quietUntil) ||
            ((mode == GyroMode::Touch) && !gyroThumbDown.load())) {
            carryX = carryY = 0.0;
            return;
        }

        // Yaw about gravity's up axis (degrees per second), and pitch about
        // the screen's horizontal axis, which is the device's y in landscape.
        const CMRotationRate rate = motion.rotationRate;
        const CMAcceleration g = motion.gravity;
        const double gLength = std::sqrt(g.x * g.x + g.y * g.y + g.z * g.z);
        if (gLength < 0.1) {
            return;
        }

        double yaw = (rate.x * g.x + rate.y * g.y + rate.z * g.z) / gLength * (180.0 / M_PI);
        double pitch = -rate.y * sign * (180.0 / M_PI);
        auto deadZone = [](double value) {
            const double magnitude = std::fabs(value);
            if (magnitude < GyroDeadZone) {
                return value * (magnitude / GyroDeadZone);
            }

            return value;
        };

        yaw = deadZone(yaw);
        pitch = deadZone(pitch);
        const double scale = GyroCountsPerDegree * LookSens[gyroSensIndex.load()] * dt;
        carryX += yaw * scale;
        carryY += pitch * scale;
        const int countsX = int(carryX);
        const int countsY = int(carryY);
        carryX -= countsX;
        carryY -= countsY;
        if ((countsX != 0) || (countsY != 0)) {
            sote::platform::ios_add_look(countsX, countsY);
        }
    }];
}

- (void)updateLandscapeSign {
    const UIDeviceOrientation orientation = UIDevice.currentDevice.orientation;
    if (orientation == UIDeviceOrientationLandscapeLeft) {
        gyroLandscapeSign.store(1);
    }
    else if (orientation == UIDeviceOrientationLandscapeRight) {
        gyroLandscapeSign.store(-1);
    }
}

- (void)dealloc {
    [_motion stopDeviceMotionUpdates];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

@end

void sote_touch_prepare_controls(NSURL *documents) {
    // The game reads its on-foot scheme from sote_controls.json at startup;
    // write the player's choice (Modern unless set to Classic) before then,
    // keeping the bike's.
    [NSUserDefaults.standardUserDefaults registerDefaults:@{ @"iosTouchClassicControls": @NO }];
    const bool classic = [NSUserDefaults.standardUserDefaults boolForKey:@"iosTouchClassicControls"];
    NSURL *file = [documents URLByAppendingPathComponent:@"sote_controls.json"];
    NSString *existing = [NSString stringWithContentsOfURL:file encoding:NSUTF8StringEncoding error:nil] ?: @"";
    NSString *bike = @"Classic";
    NSRange key = [existing rangeOfString:@"\"bike\""];
    if ((key.location != NSNotFound) && [[existing substringFromIndex:key.location] containsString:@"\"Modern\""]) {
        bike = @"Modern";
    }

    NSString *json = [NSString stringWithFormat:@"{\n  \"on_foot\": \"%@\",\n  \"bike\": \"%@\"\n}\n", classic ? @"Classic" : @"Modern", bike];
    [json writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
