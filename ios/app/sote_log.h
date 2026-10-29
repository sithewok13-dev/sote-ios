#pragma once

namespace sote {
    // Appends a line to Documents/sote-log.txt (visible in the Files app under
    // "SotE") and to the system log. Each line is flushed to disk right away,
    // so after a crash the last line shows the step that was running.
    void log(const char *format, ...) __attribute__((format(printf, 1, 2)));
}
