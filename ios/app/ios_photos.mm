// Saves RT64's captured frames as photos (see ios_photos.h).

#import "ios_photos.h"

#import <Photos/Photos.h>
#import <UIKit/UIKit.h>

#include <atomic>
#include <cstdint>

// Defined by patches/rt64/0003-ios-camera-capture.patch.
namespace RT64 {
    extern std::atomic<int> iosCaptureRequests;
    extern void (*iosCaptureCallback)(const uint8_t *bgra, uint32_t width, uint32_t height, uint32_t rowPitch);
}

static void (^savedHandler)(BOOL toPhotos) = nil;

static void reportSaved(BOOL toPhotos) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (savedHandler != nil) {
            savedHandler(toPhotos);
        }
    });
}

static NSString *photoName(void) {
    static std::atomic<int> counter{0};
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyyMMdd-HHmmss";
    return [NSString stringWithFormat:@"SotE-%@-%02d.png", [formatter stringFromDate:NSDate.date], counter++ % 100];
}

static void saveToFiles(NSData *png) {
    NSURL *documents = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *folder = [documents URLByAppendingPathComponent:@"Screenshots" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:nil];
    [png writeToURL:[folder URLByAppendingPathComponent:photoName()] atomically:YES];
    reportSaved(NO);
}

static void savePng(NSData *png) {
    const PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelAddOnly];
    if ((status != PHAuthorizationStatusAuthorized) && (status != PHAuthorizationStatusLimited)) {
        saveToFiles(png);
        return;
    }

    [PHPhotoLibrary.sharedPhotoLibrary performChanges:^{
        PHAssetCreationRequest *request = [PHAssetCreationRequest creationRequestForAsset];
        [request addResourceWithType:PHAssetResourceTypePhoto data:png options:nil];
    } completionHandler:^(BOOL success, NSError *error) {
        if (success) {
            reportSaved(YES);
        }
        else {
            saveToFiles(png);
        }
    }];
}

// RT64's present thread: copy the pixels and encode them elsewhere.
static void deliverFrame(const uint8_t *bgra, uint32_t width, uint32_t height, uint32_t rowPitch) {
    NSData *pixels = [NSData dataWithBytes:bgra length:size_t(rowPitch) * height];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)pixels);
        CGImageRef image = CGImageCreate(width, height, 8, 32, rowPitch, colorSpace,
            kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst, provider, nullptr, false, kCGRenderingIntentDefault);
        NSData *png = UIImagePNGRepresentation([UIImage imageWithCGImage:image]);
        CGImageRelease(image);
        CGDataProviderRelease(provider);
        CGColorSpaceRelease(colorSpace);
        if (png != nil) {
            savePng(png);
        }
    });
}

void sote_photos_install(void) {
    RT64::iosCaptureCallback = deliverFrame;
}

void sote_photos_request_access(void) {
    if ([PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelAddOnly] == PHAuthorizationStatusNotDetermined) {
        [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly handler:^(PHAuthorizationStatus status) {}];
    }
}

void sote_photos_capture(void) {
    RT64::iosCaptureRequests.fetch_add(1);
}

void sote_photos_set_saved_handler(void (^handler)(BOOL toPhotos)) {
    savedHandler = [handler copy];
}
