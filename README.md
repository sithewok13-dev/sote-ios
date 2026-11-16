# Star Wars: Shadows of the Empire for iPhone (SotE-Recomp iOS port)

Play **Star Wars: Shadows of the Empire** (the 1996 Nintendo 64 game) on iPhone, with touch controls. It's an unofficial port of GTTeancum's [SotE-Recomp](https://github.com/GTTeancum/SotE-Recomp), which turns the N64 game into native code: no emulator.

<!-- iPhone screenshots go here: put them in docs/ios/screenshots/ and link them with
https://raw.githubusercontent.com/sithewok13-dev/sote-ios/main/docs/ios/screenshots/<file>.jpg -->
*Screenshots from an iPhone are coming soon.*

**You need your own copy of the game: a ROM of the USA v1.2 (Rev 2) cartridge. No ROM and nothing made from it is in this repository.** The app has the game's code in it, rebuilt from your ROM, so you make your own copy of the app instead of downloading one.

## Get it: build your own

**[Shadows of the Empire builder](https://github.com/sithewok13-dev/sote-builder)** makes the app from your ROM, in your own private GitHub copy, for free, and you can do it all from your phone: share your ROM as a Google Drive or Dropbox link, tap **Run workflow**, and install the `SotE.ipa` it makes with SideStore, Feather, a signing service, AltStore or Sideloadly. [Step by step](https://github.com/sithewok13-dev/sote-builder#make-it)

There's no ready-made app to download, and please don't share the one you make: it's made from your game.

## Cool features

- **Native, not emulated:** SotE-Recomp turns the game's own code into code for the phone, and [RT64](https://github.com/rt64/rt64) draws it with Metal.
- **Touch controls** like the other ports: a stick appears where your left thumb lands, and you drag anywhere else to look. **Modern** controls (move and strafe, look separately) by default, or the N64's **Classic** turn-and-walk.
- **Gyro aiming:** off, while touching, or always, with SENS for look speed (1x to 4x).
- **A photo camera:** tap for a photo, slide sideways for a burst. Photos go straight to your Photos app.
- **A cheat:** infinite health, lives, ammo, missiles and vehicle health, a rescue from bottomless falls (Dash is put back on the last ledge he stood on), and LEVEL SELECT.
- **A start card:** CONTINUE goes straight back into the game as your last player.
- **Menus by touch:** tap a row to pick it, swipe for the D-pad.
- **Game controllers** work too.

## Thanks

This port exists because of other people's hard work:

- **[GTTeancum](https://github.com/GTTeancum)**, who made [SotE-Recomp](https://github.com/GTTeancum/SotE-Recomp), the PC port of Shadows of the Empire this is built on. When asked, GTTeancum opened its code to everyone under the MIT licence and welcomed ports like this one. Its game code, menus, modern controls and cheats are what this app runs. Thank you!
- **Wiseguy ([Mr-Wiseguy](https://github.com/Mr-Wiseguy)) and the contributors** of [N64Recomp](https://github.com/N64Recomp/N64Recomp) and [N64ModernRuntime](https://github.com/N64Recomp/N64ModernRuntime), the recompiler and runtime that make native ports of N64 games possible.
- **Darío ([DarioSamo](https://github.com/DarioSamo)), Wiseguy and the contributors** of [RT64](https://github.com/rt64/rt64) and its graphics layer [plume](https://github.com/renderbag/plume), which draw the game.
- The **[SDL](https://github.com/libsdl-org/SDL)** team, for sound and controllers.
- **LucasArts**, for making Shadows of the Empire.

## Sorry about the bugs

This is an unofficial fan project and a beta, so please expect bugs. It plays on an iPhone (an iPhone 18 Pro Max), but iPads and older iPhones haven't been tried. Holding CAMERA for selfies, Action Freeze (slide down) and the cinematic burst (slide up) are still being worked on: the view can land in the wrong place, show copies of Dash, or come out one flat colour. Now and then the screen can flash one colour for a frame. There's no multiplayer to worry about: it's a single-player game. Sorry about the rough edges. If something goes wrong, please [open an issue here](https://github.com/sithewok13-dev/sote-ios/issues), not at SotE-Recomp, and attach `sote-log.txt` from Files > SotE.

Not affiliated with or endorsed by Lucasfilm, Disney or LucasArts, or by the SotE-Recomp, N64Recomp or RT64 developers.

---

*The rest of this page is for developers: how the port is made.*

## Status

Playable on iPhone (v0.9.6): touch controls, tray, photos and bursts,
cheats, level selector, gyro, a start card on the player screen. Selfies, Action Freeze and the cinematic burst
are still being worked on.

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
  `0004` is the freeze camera: on request it pauses on the last frame (as
  RT64's debugger does) and renders it from an orbit around Dash.
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
  `0005` adds the cheat's fall rescue and tells the app when a message box
  is drawn.
  `0006` reports the game camera and Dash's position (the game's world is
  z up) and holds the game while the app freezes it; the fall rescue
  watches z.
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

The app needs code generated from the ROM, which can't live in this repo.
The owner's ROM, encrypted with AES-256 (GnuPG), is kept in their private
files repo. The `game` CI job reads it with the `JK_FILES_TOKEN` secret,
unlocks it with `SOTE_ROM_KEY`, generates the code (SotE-Recomp's
`prepare_recomp_rom.py`, N64Recomp, RSPRecomp), deletes the unlocked ROM,
builds the app with `-DSOTE_GENERATED_DIR=...`, checks that nothing like the
ROM is in it, and then deletes the game code and the app. It is a check
that the app still builds: since the app holds the recompiled game code,
nothing from this job is uploaded or published here (no release, no
artifact). Players build their own with the
[builder](https://github.com/sithewok13-dev/sote-builder), which runs
`tools/rom.py` (finds the ROM in a download, converts its byte order, checks
it), the same generation steps on Linux, then `tools/configure.sh` and the
build on a Mac, in their own private repo. Without the secrets the job is skipped.

The IPA contains no ROM: every player supplies their own. It holds the recompiled game code (as SotE-Recomp's
executable does); SotE-Recomp's `LICENSES.md` notes that its MIT grant does
not cover ROM-derived code or the game's names, art and media.

## Playing

How to make, install and play the app: see the
[builder](https://github.com/sithewok13-dev/sote-builder). On the phone the
app reads the ROM from **Files > On My iPhone > SotE** (a `.z64`, `.v64` or
`.n64` file under any name, or a `.zip` with one inside), converts it to
`sote.us.v1.2.z64` on first launch and checks it is the right game.

If anything goes wrong, `sote-log.txt` and the `logs` folder in the same
place say what happened.

## Building

CI (`.github/workflows/ios.yml`) builds the ROM-free self-test app for device
and simulator on pull requests and manual runs; the device job uploads
`SotE-unsigned.ipa`. `parts.yml`, run by hand, puts the build's ready-made
parts (RT64's host tools and CMake's check results, nothing of the game) in
the `ios-parts` release, which saves the builder about 9 Mac minutes;
`tools/parts-key.sh` names the file that fits the current sources.

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
