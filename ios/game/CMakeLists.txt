# SotE-Recomp's game layer for iOS, without anything made from the ROM.
#
# The ROM-derived part (generated/RecompiledFuncs, generated/aspMain.cpp and
# register_overlays.cpp, which includes the generated overlay table) is built
# separately and only where the ROM is; it is never part of this repository.

set(sote_src "${SOTE_RECOMP_DIR}/src")

add_library(sote_sandec STATIC "${SOTE_RECOMP_DIR}/third_party/sandec/sandec.c")
target_include_directories(sote_sandec PUBLIC "${SOTE_RECOMP_DIR}/third_party/sandec")
target_compile_options(sote_sandec PRIVATE -w)

add_library(sote_game STATIC
    "${sote_src}/controls_menu.cpp"
    "${sote_src}/control_bindings.cpp"
    "${sote_src}/modern_controls.cpp"
    "${sote_src}/modern_aim.cpp"
    "${sote_src}/frontend.cpp"
    "${sote_src}/graphics_menu.cpp"
    "${sote_src}/menu_model.cpp"
    "${sote_src}/menu_canvas.cpp"
    "${sote_src}/hud_labels.cpp"
    "${sote_src}/menu_skin.cpp"
    "${sote_src}/menu_renderer.cpp"
    "${sote_src}/hd_audio.cpp"
    "${sote_src}/pc_voices.cpp"
    "${sote_src}/hd_music.cpp"
    "${sote_src}/san_movies.cpp"
    "${sote_src}/music_replacement.cpp"
    "${sote_src}/libultra_stubs.c"
    "${sote_src}/main.cpp"
    "${sote_src}/rt64_renderer.cpp"
    sote_platform.h
    sote_platform_ios.h
    sote_platform_ios.mm
    sote_win32_compat.h
)

# RT64 writes its generated shader headers to CMAKE_BINARY_DIR/src/shaders.
add_dependencies(sote_game rt64)
target_include_directories(sote_game PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${sote_src}"
    "${CMAKE_BINARY_DIR}/src"
    "${SOTE_RUNTIME_DIR}/ultramodern/include"
    "${SOTE_RUNTIME_DIR}/librecomp/include"
    "${SOTE_RUNTIME_DIR}/N64Recomp/include"
    "${SOTE_RUNTIME_DIR}/thirdparty"
    "${SOTE_RUNTIME_DIR}/thirdparty/concurrentqueue"
    "${SOTE_RT64_DIR}/include"
    "${SOTE_RT64_DIR}/src"
    "${SOTE_RT64_DIR}/src/rhi"
    "${SOTE_RT64_DIR}/src/render"
    "${SOTE_RT64_DIR}/src/contrib"
    "${SOTE_RT64_DIR}/src/contrib/plume"
    "${SOTE_RT64_DIR}/src/contrib/imgui"
    "${SOTE_RT64_DIR}/src/contrib/hlslpp/include"
)
target_compile_options(sote_game PRIVATE
    $<$<COMPILE_LANGUAGE:C>:-Wno-implicit-function-declaration>
    $<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>
    # std::jthread is still behind this flag in Apple's libc++.
    $<$<COMPILE_LANGUAGE:CXX,OBJCXX>:-fexperimental-library>
    -Wno-deprecated-declarations
)
target_link_libraries(sote_game PUBLIC rt64 librecomp ultramodern SDL2-static sote_sandec)
