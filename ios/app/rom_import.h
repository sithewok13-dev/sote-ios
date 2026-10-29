#pragma once

#include <filesystem>
#include <string>

namespace sote {
    // The name SotE-Recomp's main() looks for first in its data directory.
    inline constexpr const char *kRomFileName = "sote.us.v1.2.z64";

    // Finds the player's own ROM in `directory` and makes sure SotE-Recomp can
    // load it: accepts .z64, .v64 and .n64 files under any name, or a .zip
    // holding one, and writes a big-endian (.z64) copy named kRomFileName.
    // Returns false with a message for the player if there is no usable ROM.
    bool import_rom(const std::filesystem::path &directory, std::string &message);
}
