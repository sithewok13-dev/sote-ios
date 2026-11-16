#!/bin/sh
# Prints the name of the ready-made parts that fit these sources and this Mac's
# tools: sote-parts-<16 hex>.tar.xz. parts.yml makes it; the builder uses it when
# the name matches (github.com/sithewok13-dev/sote-builder).
set -e
cd "$(dirname "$0")/.."
{
    xcodebuild -version 2>/dev/null || echo "no xcode"
    cmake --version | head -1
    git ls-tree HEAD third_party
    find CMakeLists.txt ios patches -name 'CMakeLists.txt' -o -name '*.patch' -o -name '*.cmake' -o -name '*.in' \
        | LC_ALL=C sort | while read -r f; do echo "$f"; cat "$f"; done
    cat tools/configure.sh tools/configure-seed.py
} | shasum -a 256 | cut -c1-16 | sed 's/^/sote-parts-/; s/$/.tar.xz/'
