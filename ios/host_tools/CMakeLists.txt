# RT64's build-time tools, built for the machine running the build.
#
# RT64 runs file_to_c and spirv_cross_msl while it builds, so when the app is
# cross-compiled for iOS they must be host executables, not iOS ones. The top
# level CMakeLists.txt configures and builds this project at configure time and
# hands the result to RT64 as RT64_HOST_TOOLS_DIR.

cmake_minimum_required(VERSION 3.20)
project(SotEHostTools LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(NOT RT64_DIR)
    message(FATAL_ERROR "Pass -DRT64_DIR=<path to third_party/rt64>")
endif()

set(SPIRV_CROSS_CLI OFF CACHE BOOL "" FORCE)
set(SPIRV_CROSS_ENABLE_TESTS OFF CACHE BOOL "" FORCE)
set(SPIRV_CROSS_SKIP_INSTALL ON CACHE BOOL "" FORCE)
add_subdirectory("${RT64_DIR}/src/contrib/spirv-cross" spirv-cross EXCLUDE_FROM_ALL)

add_executable(file_to_c "${RT64_DIR}/src/tools/file_to_c/file_to_c.cpp")

add_executable(spirv_cross_msl "${RT64_DIR}/src/tools/spirv_cross_msl/spirv_cross_msl.cpp")
target_include_directories(spirv_cross_msl PRIVATE "${RT64_DIR}/src/contrib/spirv-cross")
target_link_libraries(spirv_cross_msl PRIVATE spirv-cross-core spirv-cross-msl)
# Emit Metal Shading Language for iOS rather than macOS (see patches/rt64).
target_compile_definitions(spirv_cross_msl PRIVATE RT64_MSL_PLATFORM_IOS)

set_target_properties(file_to_c spirv_cross_msl PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
