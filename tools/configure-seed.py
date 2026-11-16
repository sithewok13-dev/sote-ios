#!/usr/bin/env python3
"""Turns a configured build's CMakeCache.txt into a seed for the next configure.

  python3 tools/configure-seed.py build/CMakeCache.txt seed.cmake

With Xcode, each of CMake's checks (does this header exist, does this flag work) runs
xcodebuild and takes about 2 seconds; there are a couple of hundred, so configuring
takes 8 minutes. Their results only depend on Xcode, CMake and the sources, so the
"ios-parts" release keeps them (parts.yml), and `cmake -C seed.cmake` skips the checks.
Only check results are kept, recognised by the help text CMake's check modules give
them; nothing with a path.
"""
import re
import sys

CHECK_HELP = ("Test ", "Have include", "Have includes", "Have function", "Have symbol",
              "Have library", "Have variable", "Have prototype")


def main(cache, out):
    lines = open(cache).read().splitlines()
    seeds, help_text = [], ""
    for line in lines:
        if line.startswith("//"):
            help_text = line[2:]
            continue
        m = re.match(r"^([A-Za-z0-9_]+):INTERNAL=(.*)$", line)
        if m and help_text.startswith(CHECK_HELP) and not m.group(1).startswith("CMAKE_"):
            name, value = m.groups()
            if "/" in value or '"' in value or "\\" in value:
                continue
            seeds.append(f'set({name} "{value}" CACHE INTERNAL "{help_text}")')
        if not line.startswith("//"):
            help_text = ""
    with open(out, "w") as f:
        f.write("# CMake check results from tools/configure-seed.py (ios-parts)\n")
        f.write("\n".join(sorted(seeds)) + "\n")
    print(f"{len(seeds)} check results in {out}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
