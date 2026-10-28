// iOS shell for the Shadows of the Empire port.
//
// For now it runs two checks on the device and shows the results:
//  - can librecomp's rdram reservation be made (memory_probe.cpp)?
//  - does plume's Metal backend present through the UIKit glue (plume_clear.cpp)?
// The screen is cleared green if both pass, amber if only rendering works.

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#include <memory>
#include <string>

#include "memory_probe.h"
#include "plume_clear.h"

@interface SoteMetalView : UIView
@end

@implementation SoteMetalView
+ (Class)layerClass {
    return [CAMetalLayer class];
}
@end

@interface SoteViewController : UIViewController
@end

@implementation SoteViewController {
    SoteMetalView *_metalView;
    UILabel *_statusLabel;
    CADisplayLink *_displayLink;
    std::unique_ptr<sote::PlumeClear> _renderer;
    bool _memoryOk;
}

- (void)loadView {
    _metalView = [[SoteMetalView alloc] initWithFrame:UIScreen.mainScreen.bounds];
    _metalView.contentScaleFactor = UIScreen.mainScreen.nativeScale;
    self.view = _metalView;

    _statusLabel = [[UILabel alloc] init];
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _statusLabel.numberOfLines = 0;
    _statusLabel.textColor = UIColor.whiteColor;
    _statusLabel.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
    [_metalView addSubview:_statusLabel];
    UILayoutGuide *safe = _metalView.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_statusLabel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [_statusLabel.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        [_statusLabel.topAnchor constraintEqualToAnchor:safe.topAnchor constant:16],
    ]];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (_displayLink != nil) {
        return;
    }

    std::string memoryReport = sote::probe_rdram_reservation(_memoryOk);
    NSLog(@"%s", memoryReport.c_str());

    _renderer = sote::PlumeClear::create((__bridge void *)_metalView, (__bridge void *)_metalView.layer);
    const char *renderReport = _renderer ? "plume: Metal swap chain OK" : "plume: Metal setup failed";
    NSLog(@"%s", renderReport);

    _statusLabel.text = [NSString stringWithFormat:@"Shadows of the Empire (iOS shell)\n%s\n%s",
        memoryReport.c_str(), renderReport];

    if (_renderer) {
        _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(renderFrame:)];
        [_displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (_renderer) {
        _renderer->resize();
    }
}

- (void)renderFrame:(CADisplayLink *)link {
    if (_memoryOk) {
        _renderer->render(0.05f, 0.35f, 0.10f);
    } else {
        _renderer->render(0.45f, 0.30f, 0.0f);
    }
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (BOOL)prefersHomeIndicatorAutoHidden {
    return YES;
}
@end

@interface SoteSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

@implementation SoteSceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
    self.window.rootViewController = [[SoteViewController alloc] init];
    [self.window makeKeyAndVisible];
}
@end

@interface SoteAppDelegate : UIResponder <UIApplicationDelegate>
@end

@implementation SoteAppDelegate
- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *configuration = [[UISceneConfiguration alloc] initWithName:@"Default" sessionRole:connectingSceneSession.role];
    configuration.delegateClass = [SoteSceneDelegate class];
    return configuration;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([SoteAppDelegate class]));
    }
}
