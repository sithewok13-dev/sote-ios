// The CHEAT button's switch and sound (see ios_cheat.h).

#import "ios_cheat.h"

#import <AVFoundation/AVFoundation.h>

#include <algorithm>
#include <cmath>
#include <vector>

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

// The built-in cheat sound, made here rather than taken from any game: a
// charging sweep that lands on a low Imperial thud and two bright tones,
// over a power hum. About 0.9 s, 44.1 kHz mono 16-bit WAV.
static NSData *cheatSoundWave(void) {
    constexpr int Rate = 44100;
    constexpr double Length = 0.95;
    const int count = int(Rate * Length);
    std::vector<int16_t> samples(size_t(count), 0);
    double sweepPhase = 0.0;
    double thudPhase = 0.0;
    for (int i = 0; i < count; i++) {
        const double t = double(i) / Rate;
        double v = 0.0;

        // Power hum under everything.
        const double humEnvelope = std::min(1.0, t / 0.08) * std::min(1.0, (Length - t) / 0.3);
        v += 0.22 * humEnvelope * (std::sin(2 * M_PI * 49 * t) + 0.6 * std::sin(2 * M_PI * 98 * t) + 0.3 * std::sin(2 * M_PI * 147 * t));

        // Charging sweep, 180 Hz to 1.2 kHz.
        if (t < 0.45) {
            const double frequency = 180.0 * std::pow(1200.0 / 180.0, t / 0.45);
            sweepPhase += 2 * M_PI * frequency / Rate;
            const double sweepEnvelope = std::sin(M_PI * t / 0.45);
            v += 0.22 * sweepEnvelope * (std::sin(sweepPhase) + 0.25 * std::sin(2 * sweepPhase));
        }

        // The landing: a pitched-down thud and two bright tones.
        if (t >= 0.42) {
            const double u = t - 0.42;
            const double thudFrequency = 40.0 + 40.0 * std::exp(-u / 0.08);
            thudPhase += 2 * M_PI * thudFrequency / Rate;
            v += 0.6 * std::exp(-u / 0.22) * std::sin(thudPhase);
            v += 0.16 * std::exp(-u / 0.25) * std::sin(2 * M_PI * 1318.5 * u);
            if (u >= 0.07) {
                const double w = u - 0.07;
                v += 0.16 * std::exp(-w / 0.3) * std::sin(2 * M_PI * 1975.5 * w);
            }
        }

        samples[size_t(i)] = int16_t(std::tanh(v) * 30000.0);
    }

    NSMutableData *wave = [NSMutableData data];
    auto put32 = [&](uint32_t value) { [wave appendBytes:&value length:4]; };
    auto put16 = [&](uint16_t value) { [wave appendBytes:&value length:2]; };
    const uint32_t dataBytes = uint32_t(count * 2);
    [wave appendBytes:"RIFF" length:4];
    put32(36 + dataBytes);
    [wave appendBytes:"WAVEfmt " length:8];
    put32(16);
    put16(1);
    put16(1);
    put32(Rate);
    put32(Rate * 2);
    put16(2);
    put16(16);
    [wave appendBytes:"data" length:4];
    put32(dataBytes);
    [wave appendBytes:samples.data() length:dataBytes];
    return wave;
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
        static NSData *builtIn = nil;
        if (builtIn == nil) {
            builtIn = cheatSoundWave();
        }

        player = [[AVAudioPlayer alloc] initWithData:builtIn error:nil];
        [player play];
        return YES;
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
