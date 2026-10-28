#include "memory_probe.h"

#include <cerrno>
#include <cstdio>
#include <cstring>

#include <sys/mman.h>

#include "librecomp/addresses.hpp"

namespace sote {
    std::string probe_rdram_reservation(bool &ok) {
        constexpr size_t mib = 1024 * 1024;
        char report[256];
        ok = false;

        void *base = mmap(nullptr, recomp::allocation_size, PROT_NONE, MAP_ANON | MAP_PRIVATE, -1, 0);
        if (base == MAP_FAILED) {
            snprintf(report, sizeof(report), "rdram: reserving %zu MiB failed: %s",
                recomp::allocation_size / mib, strerror(errno));
            return report;
        }

        if (mprotect(base, recomp::mem_size, PROT_READ | PROT_WRITE) == -1) {
            snprintf(report, sizeof(report), "rdram: reserved %zu MiB, committing %zu MiB failed: %s",
                recomp::allocation_size / mib, recomp::mem_size / mib, strerror(errno));
            munmap(base, recomp::allocation_size);
            return report;
        }

        // Touch the first and last committed bytes so the pages are really backed.
        volatile uint8_t *bytes = static_cast<volatile uint8_t *>(base);
        bytes[0] = 0x5A;
        bytes[recomp::mem_size - 1] = 0xA5;
        ok = (bytes[0] == 0x5A) && (bytes[recomp::mem_size - 1] == 0xA5);

        snprintf(report, sizeof(report), "rdram: reserved %zu MiB, committed %zu MiB: %s",
            recomp::allocation_size / mib, recomp::mem_size / mib, ok ? "OK" : "readback failed");
        munmap(base, recomp::allocation_size);
        return report;
    }
}
