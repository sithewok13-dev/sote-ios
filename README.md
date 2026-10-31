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
| iOS shell: UIKit app, plume on Metal, rdram reservation probe | works on device (0.1.2) |
| RT64 on iOS: builds, 56 shaders compiled to Metal libraries | builds (0.2.0); not yet run on device |
| Game layer: SotE-Recomp's code (now MIT) on iOS | compiles for iOS; first playable build pending (0.4.0) |
| Touch controls, tray, camera, cheats, level selector, gyro | 0.8.0 |

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
- `third_party/rt64`: the renderer, built for iOS with `patches/rt64` (see below).
- `third_party/SotE-Recomp`: GTTeancum's PC port (MIT), pinned at `7aec3d4`.
  Its game code becomes the game layer; its patches to the runtime, RT64 and
  plume are applied by `CMakeLists.txt` before ours. Its own submodules are
  not needed (the ones here are the same commits).
- `third_party/SDL`: SDL 2.32.10, built statically for iOS. RT64 needs it, and
  the game layer uses it for controllers and audio.
- `ios/host_tools/`: builds RT64's shader tools (`file_to_c`, `spirv_cross_msl`)
  for the build machine; CMake runs it at configure time. RT64 runs them during
  the build, so iOS builds of them would be useless.
- `ios/plume/plume_apple_uikit.mm`: UIKit replacement for plume's AppKit-only
  `plume_apple.mm`, swapped in by `CMakeLists.txt` (no upstream patch).
- `patches/rt64/`: `0001` makes RT64 build for iOS: keeps the iOS deployment
  target, compiles Metal shaders for `iphoneos`/`iphonesimulator`, uses the host
  tools and our SDL, drops the desktop file dialog (nfd), IOKit and the texture
  tools, and has `spirv_cross_msl` emit iOS Metal with Tier 2 argument
  buffers (at Tier 1 it moves writable textures out of the argument buffers
  into slots plume never binds, so every compute shader writing a texture,
  RT64's texture decoder included, wrote nothing: the black screen).
  `0002` logs RT64's present path (swap chain resize, empty swap chain,
  failed acquire or present) while the game shows a black screen.
  `0003` copies presented frames for the camera button.
- `patches/plume/`: small fixes applied to plume by `CMakeLists.txt` at
  configure time. `0001` skips Mac-only Metal calls (`MTLDevice.location`,
  `CAMetalLayer.displaySyncEnabled`) that abort on iOS. `0002` lets Metal
  copies read and write swap chain drawables (they were cast to the wrong
  type, crashing SotE-Recomp's pause-menu snapshot) and adds texture-to-buffer
  copies, which SotE-Recomp's screen capture uses. `0003` logs failed
  command buffers and failed texture creations, which Metal otherwise only
  records silently.
  `0004` checks texture buffer views (which RT64's compute shaders read
  vertex data through): Metal returns nil past a width limit that is lower
  on iOS, so it logs that and retries with the view clamped.
  `0005` also logs the details of a failed command buffer (with shader
  validation on, the failing function and resource).
  `0006` keeps resources alive while the GPU still uses them on iOS
  (retained command buffers, no residency sets): 0.6.0 hit a GPU page fault
  after a few minutes, after which iOS ignores all of the app's GPU work.
- `patches/sote-recomp/`: `0001` ports SotE-Recomp's Windows-only code: its
  window, message pump, crash reports and executable path go behind
  `#ifdef _WIN32` with iOS versions; `main()` becomes `sote_main()`;
  `menu_renderer.cpp` gains Metal shaders; `rt64_renderer.cpp` passes the
  Metal view to RT64.
  `0002` lets the app force SotE-Recomp's compatibility graphics profile
  (no MSAA, standard color), to test whether those cause the black screen.
  `0003` feeds the on-screen controls (`ios/app/touch_controls.mm`) into the
  game's N64 input.
  `0004` lets the level selector jump to a level's first event.
- `ios/game/`: the `sote_game` library: SotE-Recomp's game code plus
  `sote_platform_ios.mm` (Documents folder, Metal view, keyboard stub) and
  `sote_win32_compat.h` (the few Win32 names it uses elsewhere: key codes,
  tick count, process id). Nothing made from the ROM is in it: the generated
  code and `register_overlays.cpp` are built separately, only where the ROM is.
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

Result on an iPhone 18 Pro Max, iOS 27.2, sideloaded with Feather (0.1.2,
2026-10-29): both OK, green. librecomp's memory layout works unchanged; no
extended-virtual-addressing entitlement is needed.

## Building the playable app

The app needs code generated from the ROM, which can't live in this repo. With
the owner's agreement (2026-10-29), `rom/sote.z64.gpg` holds their ROM
encrypted with AES-256 (GnuPG). The `game` CI job unlocks it with the
`SOTE_ROM_KEY` Actions secret, generates the code (SotE-Recomp's
`prepare_recomp_rom.py`, N64Recomp, RSPRecomp), deletes the unlocked ROM,
builds the app with `-DSOTE_GENERATED_DIR=...` and uploads
`SotE-iOS-<version>.ipa`, kept for 30 days. Without the secret the job is
skipped.

Like SotE-Recomp's Windows release, the IPA contains no ROM: every player
supplies their own. It holds the recompiled game code (as SotE-Recomp's
executable does); SotE-Recomp's `LICENSES.md` notes that its MIT grant does
not cover ROM-derived code or the game's names, art and media.

## Playing

1. Install `SotE-iOS-<version>.ipa` with Feather, Sideloadly, AltStore or
   similar.
2. Copy your own *Shadows of the Empire* (USA, v1.2 / Rev 2) ROM into
   **Files > On My iPhone > SotE**: a `.z64`, `.v64` or `.n64` file under any
   name, or a `.zip` with one inside. The app converts it to
   `sote.us.v1.2.z64` on first launch and checks it is the right game.
3. Open SotE. The on-screen controls follow the house style of the other
   ports (`jk-files` docs/HOUSE_STYLE.md, section 3):
   - a floating stick in the lower left (hidden until your thumb lands);
     drag anywhere else to look. CONTROLS in the tray picks Modern (the
     default: move and strafe, look separately, like the other ports) or
     Classic (the N64's own turn-and-walk);
   - A, B and the C buttons on the right, Z under L, L and R at the top;
   - START at the bottom: tap for Start (begin, pause, skip story screens);
     hold 0.45 s (its border fills) for the tray: CONTROLS, GYRO (off /
     while touching / always), SENS, OPACITY (slider; hold to reset),
     CAMERA, CHEAT, LEVEL SELECT (cheat on), D-PAD, LOG;
   - CAMERA (top middle, beside CHEAT): tap for a photo, slide sideways for a burst (every
     0.2 s, up to 10). Photos go to your library, or to Files > SotE >
     Screenshots without access;
   - CHEAT (shown from the tray): hold 0.5 s to switch infinite health,
     lives, ammo, missiles and vehicle health; it plays a random clip from
     Files > SotE > Cheat Sounds (your own clips);
   A game controller works too.

If anything goes wrong, `sote-log.txt` and the `logs` folder in the same
place say what happened.

## Building

CI (`.github/workflows/ios.yml`) builds for device and simulator on every
push. The device job uploads `SotE-unsigned.ipa`; sign it with your own Apple
ID through Sideloadly, AltStore or similar to install it.

Locally on a Mac with Xcode:

```sh
git submodule update --init third_party/SotE-Recomp
git submodule update --init --recursive third_party/N64Recomp third_party/N64ModernRuntime third_party/rt64 third_party/SDL
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
