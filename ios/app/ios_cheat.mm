// The CHEAT button's switch and sound (see ios_cheat.h).

#import "ios_cheat.h"

#import <AVFoundation/AVFoundation.h>

static NSURL *documentsURL(void) {
    return [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
}

void sote_cheat_set(BOOL on) {
    const char *value = on ? "1" : "0";
    NSString *text = [NSString stringWithFormat:
        @"; Shadows of the Empire: Recompiled - cheats\n"
        @"; 1 = on, 0 = off. Saved changes apply within a second;\n"
        @"; no restart needed. The iOS CHEAT button rewrites this file.\n"
        @"\n"
        @"infinite_health = %s\n"
        @"infinite_lives = %s\n"
        @"infinite_ammo = %s\n"
        @"infinite_missiles = %s\n"
        @"infinite_vehicle_health = %s\n"
        @"rapid_fire = 0\n"
        @"rapid_fire_rate = 4\n",
        value, value, value, value, value];
    [text writeToURL:[documentsURL() URLByAppendingPathComponent:@"SOTE_CHEATS.INI"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

BOOL sote_cheat_play_sound(void) {
    static AVAudioPlayer *player = nil;
    static NSString *lastClip = nil;
    if ((player != nil) && player.isPlaying) {
        return YES;
    }

    NSURL *folder = [documentsURL() URLByAppendingPathComponent:@"Cheat Sounds" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:nil];
    NSArray<NSString *> *extensions = @[ @"mp3", @"m4a", @"wav", @"caf", @"aif", @"aiff" ];
    NSMutableArray<NSURL *> *clips = [NSMutableArray array];
    for (NSURL *file in [NSFileManager.defaultManager contentsOfDirectoryAtURL:folder includingPropertiesForKeys:nil options:0 error:nil]) {
        if ([extensions containsObject:file.pathExtension.lowercaseString]) {
            [clips addObject:file];
        }
    }

    if (clips.count == 0) {
        return NO;
    }

    if ((clips.count > 1) && (lastClip != nil)) {
        [clips filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSURL *clip, NSDictionary *bindings) {
            return ![clip.lastPathComponent isEqualToString:lastClip];
        }]];
    }

    NSURL *clip = clips[arc4random_uniform(uint32_t(clips.count))];
    lastClip = clip.lastPathComponent;
    player = [[AVAudioPlayer alloc] initWithContentsOfURL:clip error:nil];
    [player play];
    return YES;
}
