# Shadows of the Empire for iOS

A private port of Star Wars: Shadows of the Empire (N64) to iPhone and iPad,
built on [N64Recomp], [N64ModernRuntime] and [RT64] (Metal through plume).

**This repository holds no ROM, no ROM-derived code and no game data.** You
supply your own USA v1.2 (Rev 2) ROM locally; anything built from it stays
on your machine and your device. `.gitignore` blocks ROM files and the
`generated/` output.

Planning notes live in `jk-files` (branch `wip-sote-ios`).

## Status

| Step | State |
| --- | --- |
| Repo, GPL-3.0 licence, pinned submodules | done |
| iOS shell: UIKit app, plume on Metal, rdram reservation probe | written, CI builds it |
| RT64 on iOS (shader build for `iphoneos`, no SDL/nfd/IOKit) | next |
| Game layer: SotE-Recomp's code (now MIT) on iOS | blocked on the ROM |
| Touch controls (IOSTouch overlay) | later |

The game layer comes from [SotE-Recomp] by GTTeancum, who licensed its original
code under MIT on 2026-10-28 (commit `7aec3d4`, answering issue #21) and
welcomed ports. Per its `LICENSES.md`, that grant does not cover game files,
music (`Sdata/MUSIC`), artwork, fonts or ROM-derived code, so none of those
are copied here or bundled into builds. The submodules are pinned to the same
upstream commits SotE-Recomp uses.

## Layout

- `third_party/N64Recomp`: the recompiler. Runs on a desktop (Linux or macOS)
  to turn the ROM into C. Never built for iOS.
- `third_party/N64ModernRuntime`: ultramodern + librecomp, built into the app.
  Mods (LiveRecomp/sljit) stay off on iOS, since they need a JIT.
- `third_party/rt64`: the renderer. For now only its plume submodule is built
  for iOS.
- `ios/plume/plume_apple_uikit.mm`: UIKit replacement for plume's AppKit-only
  `plume_apple.mm`, swapped in by `CMakeLists.txt` (no upstream patch).
- `patches/plume/`: small fixes applied to plume by `CMakeLists.txt` at
  configure time. `0001` skips Mac-only Metal calls (`MTLDevice.location`,
  `CAMetalLayer.displaySyncEnabled`) that abort on iOS.
- `ios/app/`: the app. `memory_probe.cpp` repeats librecomp's rdram setup
  (reserve 4 GiB, commit 512 MiB) and `plume_clear.cpp` presents a cleared
  Metal swap chain.

## The shell's self-test

Launch the app on a device. It shows two lines:

- `rdram: reserved 4096 MiB, committed 512 MiB: OK` means librecomp's memory
  layout works as is. A failure means the app needs the
  `com.apple.developer.kernel.extended-virtual-addressing` entitlement, or
  librecomp's reservation has to shrink.
- `plume: Metal swap chain OK` means the renderer backend runs on iOS.

The screen turns green when both pass and amber when only rendering works.
The simulator follows macOS memory rules, so only a real device answers the
first question.

## Building

CI (`.github/workflows/ios.yml`) builds for device and simulator on every
push. The device job uploads `SotE-unsigned.ipa`; sign it with your own Apple
ID through Sideloadly, AltStore or similar to install it.

Locally on a Mac with Xcode:

```sh
git submodule update --init --recursive
cmake -S . -B build -G Xcode -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0
open build/SotEiOS.xcodeproj   # pick your team under Signing, then run on a device
```

Bundle id: `io.github.sithewok13.sote` (override with `-DSOTE_BUNDLE_ID=...`).

## Licence

GPL-3.0 (see `LICENSE`), because N64ModernRuntime is GPL-3.0. N64Recomp, RT64,
plume and SotE-Recomp's original code are MIT; SotE-Recomp's sandec is
LGPL-2.1. Credit for the PC port's game layer goes to GTTeancum.

[N64Recomp]: https://github.com/N64Recomp/N64Recomp
[N64ModernRuntime]: https://github.com/N64Recomp/N64ModernRuntime
[RT64]: https://github.com/rt64/rt64
[SotE-Recomp]: https://github.com/GTTeancum/SotE-Recomp
