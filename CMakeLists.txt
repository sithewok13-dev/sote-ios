cmake_minimum_required(VERSION 3.24)

if(CMAKE_SYSTEM_NAME STREQUAL "iOS" AND NOT CMAKE_OSX_DEPLOYMENT_TARGET)
    # plume's iOS paths assume iOS 16 or later (buffer device address).
    set(CMAKE_OSX_DEPLOYMENT_TARGET "16.0" CACHE STRING "Minimum iOS version")
endif()

project(SotEiOS VERSION 0.1.0 LANGUAGES C CXX)

set(CMAKE_C_STANDARD 17)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(SOTE_BUNDLE_ID "io.github.sithewok13.sote" CACHE STRING "iOS bundle identifier")
set(SOTE_RUNTIME_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party/N64ModernRuntime")
set(SOTE_PLUME_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party/rt64/src/contrib/plume")

foreach(dir "${SOTE_RUNTIME_DIR}" "${SOTE_PLUME_DIR}")
    if(NOT EXISTS "${dir}/CMakeLists.txt")
        message(FATAL_ERROR "${dir} is missing. Run: git submodule update --init --recursive")
    endif()
endforeach()

# ultramodern + librecomp (and N64Recomp/LiveRecomp, which librecomp links).
# Mods are not used on iOS: LiveRecomp's JIT can't run without a JIT entitlement.
add_subdirectory("${SOTE_RUNTIME_DIR}" N64ModernRuntime)

if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    enable_language(OBJC OBJCXX)

    add_subdirectory("${SOTE_PLUME_DIR}" plume)

    # plume's Apple window glue is AppKit-only; swap in the UIKit version.
    get_target_property(plume_sources plume SOURCES)
    list(REMOVE_ITEM plume_sources plume_apple.mm)
    list(APPEND plume_sources "${CMAKE_CURRENT_SOURCE_DIR}/ios/plume/plume_apple_uikit.mm")
    set_target_properties(plume PROPERTIES SOURCES "${plume_sources}")

    add_subdirectory(ios)
endif()
