cmake_minimum_required(VERSION 3.24)

if(CMAKE_SYSTEM_NAME STREQUAL "iOS" AND NOT CMAKE_OSX_DEPLOYMENT_TARGET)
    # plume's iOS paths assume iOS 16 or later (buffer device address).
    set(CMAKE_OSX_DEPLOYMENT_TARGET "16.0" CACHE STRING "Minimum iOS version")
endif()

project(SotEiOS VERSION 0.5.13 LANGUAGES C CXX)

set(CMAKE_C_STANDARD 17)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(SOTE_BUNDLE_ID "io.github.sithewok13.sote" CACHE STRING "iOS bundle identifier")
set(SOTE_GENERATED_DIR "" CACHE PATH
    "SotE-Recomp generated/ folder made from the ROM; empty builds the self-test app")
set(SOTE_RUNTIME_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party/N64ModernRuntime")
set(SOTE_RT64_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party/rt64")
set(SOTE_PLUME_DIR "${SOTE_RT64_DIR}/src/contrib/plume")
set(SOTE_SDL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party/SDL")
set(SOTE_RECOMP_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party/SotE-Recomp")

foreach(dir "${SOTE_RUNTIME_DIR}" "${SOTE_RT64_DIR}" "${SOTE_PLUME_DIR}" "${SOTE_SDL_DIR}" "${SOTE_RECOMP_DIR}")
    if(NOT EXISTS "${dir}/CMakeLists.txt")
        message(FATAL_ERROR "${dir} is missing. Run: git submodule update --init --recursive")
    endif()
endforeach()

# Applies a patch to a submodule's working tree once (skipped if already applied).
function(sote_apply_patch repo patch)
    execute_process(COMMAND git -C "${repo}" apply --reverse --check "${patch}"
        RESULT_VARIABLE already_applied OUTPUT_QUIET ERROR_QUIET)
    if(already_applied EQUAL 0)
        return()
    endif()
    execute_process(COMMAND git -C "${repo}" apply "${patch}" RESULT_VARIABLE result)
    if(NOT result EQUAL 0)
        message(FATAL_ERROR "Could not apply ${patch} to ${repo}")
    endif()
    message(STATUS "Applied ${patch}")
endfunction()

# SotE-Recomp's own fixes to the runtime, RT64 and plume (MIT, see
# third_party/SotE-Recomp/LICENSES.md), applied in its numbered order. The
# target library is named in each file name.
file(GLOB sote_recomp_patches "${SOTE_RECOMP_DIR}/patches/*.patch")
list(SORT sote_recomp_patches)
foreach(patch IN LISTS sote_recomp_patches)
    get_filename_component(patch_name "${patch}" NAME)
    if(patch_name MATCHES "-n64modernruntime-")
        sote_apply_patch("${SOTE_RUNTIME_DIR}" "${patch}")
    elseif(patch_name MATCHES "-rt64-")
        sote_apply_patch("${SOTE_RT64_DIR}" "${patch}")
    elseif(patch_name MATCHES "-plume-")
        sote_apply_patch("${SOTE_PLUME_DIR}" "${patch}")
    else()
        message(FATAL_ERROR "Don't know which library ${patch_name} patches")
    endif()
endforeach()

# Our iOS port of SotE-Recomp's game layer (see ios/game).
file(GLOB sote_port_patches "${CMAKE_CURRENT_SOURCE_DIR}/patches/sote-recomp/*.patch")
list(SORT sote_port_patches)
foreach(patch IN LISTS sote_port_patches)
    sote_apply_patch("${SOTE_RECOMP_DIR}" "${patch}")
endforeach()

# ultramodern + librecomp (and N64Recomp/LiveRecomp, which librecomp links).
# Mods are not used on iOS: LiveRecomp's JIT can't run without a JIT entitlement.
add_subdirectory("${SOTE_RUNTIME_DIR}" N64ModernRuntime)

if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    enable_language(OBJC OBJCXX)

    target_compile_options(LiveRecomp PRIVATE
        -include "${CMAKE_CURRENT_SOURCE_DIR}/ios/compat/sljit_ios.h")

    foreach(sub IN ITEMS rt64 plume)
        file(GLOB sub_patches "${CMAKE_CURRENT_SOURCE_DIR}/patches/${sub}/*.patch")
        list(SORT sub_patches)
        foreach(patch IN LISTS sub_patches)
            if(sub STREQUAL "rt64")
                sote_apply_patch("${SOTE_RT64_DIR}" "${patch}")
            else()
                sote_apply_patch("${SOTE_PLUME_DIR}" "${patch}")
            endif()
        endforeach()
    endforeach()

    # RT64's shader tools run during the build, so build them for this machine.
    set(host_tools_build "${CMAKE_BINARY_DIR}/host_tools")
    if(NOT EXISTS "${host_tools_build}/bin/spirv_cross_msl")
        message(STATUS "Building RT64 host tools in ${host_tools_build}")
        execute_process(
            COMMAND "${CMAKE_COMMAND}" -E env --unset=SDKROOT --unset=IPHONEOS_DEPLOYMENT_TARGET
                "${CMAKE_COMMAND}" -S "${CMAKE_CURRENT_SOURCE_DIR}/ios/host_tools" -B "${host_tools_build}"
                -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release "-DRT64_DIR=${SOTE_RT64_DIR}"
            RESULT_VARIABLE result)
        if(NOT result EQUAL 0)
            message(FATAL_ERROR "Configuring RT64 host tools failed")
        endif()
        execute_process(
            COMMAND "${CMAKE_COMMAND}" -E env --unset=SDKROOT --unset=IPHONEOS_DEPLOYMENT_TARGET
                "${CMAKE_COMMAND}" --build "${host_tools_build}" --parallel
            RESULT_VARIABLE result)
        if(NOT result EQUAL 0)
            message(FATAL_ERROR "Building RT64 host tools failed")
        endif()
    endif()
    set(RT64_HOST_TOOLS_DIR "${host_tools_build}/bin")

    # Compile RT64's Metal shaders for the SDK being targeted.
    if(CMAKE_OSX_SYSROOT MATCHES "[Ss]imulator")
        set(RT64_METAL_SDK "iphonesimulator")
    else()
        set(RT64_METAL_SDK "iphoneos")
    endif()

    # SDL2: RT64 needs it, and the game layer uses it for controllers and audio.
    set(SDL_SHARED OFF CACHE BOOL "" FORCE)
    set(SDL_STATIC ON CACHE BOOL "" FORCE)
    set(SDL_TEST OFF CACHE BOOL "" FORCE)
    add_subdirectory("${SOTE_SDL_DIR}" SDL EXCLUDE_FROM_ALL)
    set(SDL2_INCLUDE_DIRS "$<TARGET_PROPERTY:SDL2-static,INTERFACE_INCLUDE_DIRECTORIES>")
    set(SDL2_LIBRARIES SDL2-static)

    set(RT64_STATIC TRUE)
    add_subdirectory("${SOTE_RT64_DIR}" rt64)

    # plume's Apple window glue is AppKit-only; swap in the UIKit version.
    get_target_property(plume_sources plume SOURCES)
    list(REMOVE_ITEM plume_sources plume_apple.mm)
    list(APPEND plume_sources "${CMAKE_CURRENT_SOURCE_DIR}/ios/plume/plume_apple_uikit.mm")
    set_target_properties(plume PROPERTIES SOURCES "${plume_sources}")
    # RT64 turns Retina off for macOS; on iOS render at the screen's native scale.
    target_compile_definitions(plume PRIVATE PLUME_APPLE_RETINA_ENABLED)

    add_subdirectory(ios/game)
    add_subdirectory(ios)
endif()
