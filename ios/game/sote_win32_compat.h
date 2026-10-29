#pragma once

// Stand-ins for the few Win32 names SotE-Recomp uses outside its window and
// crash-report code, so frontend.cpp and main.cpp keep their logic unchanged
// on iOS. Values match the Win32 headers.

#include <chrono>
#include <cstdint>

#include <pthread.h>
#include <unistd.h>

#include "sote_platform.h"

using DWORD = uint32_t;
using ULONGLONG = unsigned long long;
using HWND = void *;

#ifndef MAX_PATH
#define MAX_PATH 1024
#endif

enum : int {
    VK_LBUTTON = 0x01,
    VK_RBUTTON = 0x02,
    VK_MBUTTON = 0x04,
    VK_TAB = 0x09,
    VK_RETURN = 0x0D,
    VK_ESCAPE = 0x1B,
    VK_SPACE = 0x20,
    VK_LEFT = 0x25,
    VK_UP = 0x26,
    VK_RIGHT = 0x27,
    VK_DOWN = 0x28,
    VK_NUMPAD2 = 0x62,
    VK_NUMPAD4 = 0x64,
    VK_NUMPAD6 = 0x66,
    VK_NUMPAD8 = 0x68,
    VK_F1 = 0x70,
    VK_F11 = 0x7A,
};

inline short GetAsyncKeyState(int virtual_key) {
    return sote::platform::key_down(virtual_key) ? static_cast<short>(0x8000) : 0;
}

inline ULONGLONG GetTickCount64() {
    return static_cast<ULONGLONG>(std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count());
}

inline DWORD GetCurrentProcessId() {
    return static_cast<DWORD>(getpid());
}

inline DWORD GetCurrentThreadId() {
    uint64_t id = 0;
    pthread_threadid_np(nullptr, &id);
    return static_cast<DWORD>(id);
}

// iOS shows one app at a time: if the game is running, it is in front.
inline HWND GetForegroundWindow() {
    return reinterpret_cast<HWND>(1);
}

inline DWORD GetWindowThreadProcessId(HWND, DWORD *process_id) {
    if (process_id != nullptr) {
        *process_id = GetCurrentProcessId();
    }

    return 0;
}

#include <cerrno>
#include <cstdio>

// MSVC's checked fopen; returns 0 on success like the original.
inline int fopen_s(FILE **file, const char *path, const char *mode) {
    *file = std::fopen(path, mode);
    return *file != nullptr ? 0 : errno;
}
