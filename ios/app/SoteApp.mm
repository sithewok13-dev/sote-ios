// iOS shell for the Shadows of the Empire port.
//
// For now it runs two checks on the device and shows the results:
//  - can librecomp's rdram reservation be made (memory_probe.cpp)?
//  - does plume's Metal backend present through the UIKit glue (plume_clear.cpp)?
// The screen is cleared green if both pass, amber if only rendering works.
// Every step is written to Documents/sote-log.txt (Files app > SotE), so if
// the app crashes, the log's last line shows where.
//
// Built with the game (SOTE_WITH_GAME), it runs the memory check, then starts
// SotE-Recomp's main() on its own thread once the ROM is in Documents.

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#include <sys/utsname.h>

#include <memory>
#include <string>

#include "memory_probe.h"
#include "plume_clear.h"
#include "sote_log.h"

#if SOTE_WITH_GAME
#include "rom_import.h"
#include "sote_platform_ios.h"

static NSString *lastLines(NSURL *file, NSUInteger count);
#endif

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
    bool _started;
    bool _gameStopped;
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
    if (_started) {
        return;
    }

    _started = true;
    _statusLabel.text = @"Shadows of the Empire (iOS shell)\nrunning checks...";
    sote::log("view appeared, %.0fx%.0f points, scale %.1f",
        _metalView.bounds.size.width, _metalView.bounds.size.height, _metalView.contentScaleFactor);

    // Let the status text reach the screen before the checks run.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self runChecks];
    });
}

- (void)runChecks {
    sote::log("memory probe: start");
    std::string memoryReport = sote::probe_rdram_reservation(_memoryOk);
    sote::log("%s", memoryReport.c_str());
#if SOTE_WITH_GAME
    [self startGameWithMemoryReport:memoryReport];
    return;
#endif
    _statusLabel.text = [NSString stringWithFormat:@"Shadows of the Empire (iOS shell)\n%s\nplume: starting...",
        memoryReport.c_str()];

    _renderer = sote::PlumeClear::create((__bridge void *)_metalView, (__bridge void *)_metalView.layer);
    const char *renderReport = _renderer ? "plume: Metal swap chain OK" : "plume: Metal setup failed";
    sote::log("%s", renderReport);

    _statusLabel.text = [NSString stringWithFormat:@"Shadows of the Empire (iOS shell)\n%s\n%s",
        memoryReport.c_str(), renderReport];

    if (_renderer) {
        _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(renderFrame:)];
        [_displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
}

#if SOTE_WITH_GAME
- (void)startGameWithMemoryReport:(const std::string &)memoryReport {
    NSURL *documents = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    std::string romMessage;
    if (!sote::import_rom(documents.path.fileSystemRepresentation, romMessage)) {
        sote::log("game: %s", romMessage.c_str());
        _statusLabel.text = [NSString stringWithFormat:
            @"Shadows of the Empire\n%s\n\n"
            @"%s\n\n"
            @"Copy your own Shadows of the Empire (USA) ROM into\n"
            @"Files > On My iPhone > SotE\n"
            @"(.z64, .v64, .n64 or a .zip with one inside),\n"
            @"then close and reopen this app.",
            memoryReport.c_str(), romMessage.c_str()];
        return;
    }

    sote::log("game: ROM ready, starting");
    _statusLabel.text = @"Shadows of the Empire\nstarting...";
    sote::platform::ios_set_game_view((__bridge void *)_metalView, (__bridge void *)_metalView.layer);

    __weak SoteViewController *weakSelf = self;
    NSThread *gameThread = [[NSThread alloc] initWithBlock:^{
        static char programName[] = "SotE";
        char *argv[] = {programName, nullptr};
        const int result = sote_main(1, argv);
        sote::log("game: main returned %d", result);
        NSString *errors = lastLines([documents URLByAppendingPathComponent:@"logs/sote-latest-errors.log"], 12);
        dispatch_async(dispatch_get_main_queue(), ^{
            SoteViewController *strongSelf = weakSelf;
            if (strongSelf != nil) {
                strongSelf->_gameStopped = true;
                strongSelf->_statusLabel.hidden = NO;
                strongSelf->_statusLabel.text = [NSString stringWithFormat:
                    @"Shadows of the Empire\nThe game stopped (code %d).\n"
                    @"Details: Files > SotE > logs\n\n%@", result, errors];
            }
        });
    }];
    gameThread.name = @"SotE game";
    gameThread.stackSize = 16 * 1024 * 1024;
    gameThread.qualityOfService = NSQualityOfServiceUserInteractive;
    [gameThread start];

    // Until the game is known to draw, show the game's own log live over the
    // view, so a screenshot shows where it got to. Tap to hide or show it.
    _statusLabel.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    _statusLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
    _metalView.userInteractionEnabled = YES;
    [_metalView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleLog)]];
    NSURL *logs = [documents URLByAppendingPathComponent:@"logs"];
    [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *timer) {
        SoteViewController *strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf->_gameStopped) {
            [timer invalidate];
            return;
        }

        strongSelf->_statusLabel.text = [NSString stringWithFormat:@"SotE log (tap to hide)\n%@\n-- errors --\n%@",
            lastLines([logs URLByAppendingPathComponent:@"sote-latest.log"], 10),
            lastLines([logs URLByAppendingPathComponent:@"sote-latest-errors.log"], 10)];
    }];
}

- (void)toggleLog {
    _statusLabel.hidden = !_statusLabel.hidden;
}

// The last `count` lines of a text file, or an empty string.
static NSString *lastLines(NSURL *file, NSUInteger count) {
    NSString *text = [NSString stringWithContentsOfURL:file encoding:NSUTF8StringEncoding error:nil];
    if (text == nil) {
        return @"";
    }

    NSArray<NSString *> *lines = [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    NSMutableArray<NSString *> *kept = [NSMutableArray array];
    for (NSString *line in lines.reverseObjectEnumerator) {
        if (line.length == 0) {
            continue;
        }

        [kept insertObject:line atIndex:0];
        if (kept.count == count) {
            break;
        }
    }

    return [kept componentsJoinedByString:@"\n"];
}
#endif

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

static void logUncaughtException(NSException *exception) {
    sote::log("uncaught exception: %s: %s", exception.name.UTF8String, exception.reason.UTF8String);
}

@implementation SoteAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    NSSetUncaughtExceptionHandler(&logUncaughtException);
    struct utsname systemInfo;
    uname(&systemInfo);
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    sote::log("SotE %s launched on %s, %s %s", version.UTF8String, systemInfo.machine,
        UIDevice.currentDevice.systemName.UTF8String, UIDevice.currentDevice.systemVersion.UTF8String);
    return YES;
}

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
