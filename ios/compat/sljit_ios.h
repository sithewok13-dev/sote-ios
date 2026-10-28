// Force-included into LiveRecomp on iOS.
//
// sljit's Apple allocator calls SLJIT_UPDATE_WX_FLAGS but only defines it in
// its macOS branch, so the iOS build fails. A no-op is correct here: mods (and
// with them sljit's JIT) are never used on iOS.
#pragma once

#ifndef SLJIT_UPDATE_WX_FLAGS
#define SLJIT_UPDATE_WX_FLAGS(from, to, enable_exec)
#endif
