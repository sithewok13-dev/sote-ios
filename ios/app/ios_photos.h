#pragma once

#import <Foundation/Foundation.h>

// The camera button's photos: RT64 copies presented frames (patches/rt64
// 0003), which are saved to the Photos library (add-only access), or to
// Documents/Screenshots in the Files app when that isn't allowed.

// Hooks RT64's capture callback up. Call once before the game starts.
void sote_photos_install(void);

// Asks for add-only Photos access if it hasn't been decided yet.
void sote_photos_request_access(void);

// Captures the next presented frame.
void sote_photos_capture(void);

// Called on the main thread after each photo is saved: true when it went to
// Photos, false when it went to Files.
void sote_photos_set_saved_handler(void (^handler)(BOOL toPhotos));
