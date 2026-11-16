#!/bin/sh
# Configures the iOS game build (Xcode project in build/), the same way for the
# builder (github.com/sithewok13-dev/sote-builder) and parts.yml.
#   tools/configure.sh <generated folder> <bundle id> [seed.cmake]
# <generated folder> is SotE-Recomp's generated/ (RecompiledFuncs, aspMain.cpp).
set -e
cd "$(dirname "$0")/.."
gen=$1 bundle=$2 seed=$3
set --
[ -n "$seed" ] && [ -f "$seed" ] && set -- -C "$seed"
cmake "$@" -S . -B build -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT=iphoneos \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 \
    "-DSOTE_BUNDLE_ID=$bundle" \
    "-DSOTE_GENERATED_DIR=$gen"
