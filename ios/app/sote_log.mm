#include "sote_log.h"

#import <Foundation/Foundation.h>

#include <cstdarg>
#include <cstdio>
#include <mutex>

#include <unistd.h>

namespace sote {
    static std::mutex log_mutex;
    static FILE *log_file = nullptr;

    static FILE *open_log() {
        NSURL *documents = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
        NSString *path = [documents URLByAppendingPathComponent:@"sote-log.txt"].path;
        // Start a fresh log on each launch.
        return fopen(path.fileSystemRepresentation, "w");
    }

    void log(const char *format, ...) {
        char line[512];
        va_list args;
        va_start(args, format);
        vsnprintf(line, sizeof(line), format, args);
        va_end(args);

        NSLog(@"[SotE] %s", line);

        std::lock_guard<std::mutex> lock(log_mutex);
        if (log_file == nullptr) {
            log_file = open_log();
            if (log_file == nullptr) {
                return;
            }
        }

        fprintf(log_file, "%s\n", line);
        fflush(log_file);
        fsync(fileno(log_file));
    }
}
