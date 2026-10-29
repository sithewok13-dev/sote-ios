#include "rom_import.h"

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <system_error>
#include <vector>

#include "miniz.h"

#include "sote_log.h"

namespace sote {
    namespace {
        // SotE-Recomp's main() also accepts these names, so they need no copy.
        const char *const kOtherAcceptedNames[] = {
            "Star Wars - Shadows of the Empire (U) (V1.2) [!].z64",
            "Star Wars - Shadows of the Empire (USA) (Rev 2).z64",
        };

        constexpr size_t kRomSize = 12 * 1024 * 1024;
        constexpr char kInternalName[] = "Shadow of the Empire";

        std::string lowercase_extension(const std::filesystem::path &path) {
            std::string extension = path.extension().string();
            std::transform(extension.begin(), extension.end(), extension.begin(),
                [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
            return extension;
        }

        bool is_rom_extension(const std::string &extension) {
            return extension == ".z64" || extension == ".v64" || extension == ".n64";
        }

        bool read_file(const std::filesystem::path &path, std::vector<uint8_t> &bytes) {
            std::ifstream file(path, std::ios::binary);
            if (!file) {
                return false;
            }

            bytes.assign(std::istreambuf_iterator<char>(file), std::istreambuf_iterator<char>());
            return true;
        }

        // Reads the first ROM-looking file inside a .zip.
        bool read_zip(const std::filesystem::path &path, std::vector<uint8_t> &bytes) {
            mz_zip_archive zip{};
            if (!mz_zip_reader_init_file(&zip, path.string().c_str(), 0)) {
                return false;
            }

            bool found = false;
            const mz_uint count = mz_zip_reader_get_num_files(&zip);
            for (mz_uint i = 0; i < count && !found; i++) {
                char name[512];
                if (mz_zip_reader_is_file_a_directory(&zip, i) ||
                    mz_zip_reader_get_filename(&zip, i, name, sizeof(name)) == 0 ||
                    !is_rom_extension(lowercase_extension(name))) {
                    continue;
                }

                size_t size = 0;
                void *data = mz_zip_reader_extract_to_heap(&zip, i, &size, 0);
                if (data != nullptr) {
                    const uint8_t *begin = static_cast<const uint8_t *>(data);
                    bytes.assign(begin, begin + size);
                    mz_free(data);
                    found = true;
                }
            }

            mz_zip_reader_end(&zip);
            return found;
        }

        // Converts byte-swapped (.v64) and little-endian (.n64) dumps to .z64.
        bool to_big_endian(std::vector<uint8_t> &rom) {
            if (rom.size() < 0x40 || rom.size() % 4 != 0) {
                return false;
            }

            if (rom[0] == 0x80 && rom[1] == 0x37 && rom[2] == 0x12 && rom[3] == 0x40) {
                return true;
            }

            if (rom[0] == 0x37 && rom[1] == 0x80 && rom[2] == 0x40 && rom[3] == 0x12) {
                for (size_t i = 0; i < rom.size(); i += 2) {
                    std::swap(rom[i], rom[i + 1]);
                }

                return true;
            }

            if (rom[0] == 0x40 && rom[1] == 0x12 && rom[2] == 0x37 && rom[3] == 0x80) {
                for (size_t i = 0; i < rom.size(); i += 4) {
                    std::swap(rom[i], rom[i + 3]);
                    std::swap(rom[i + 1], rom[i + 2]);
                }

                return true;
            }

            return false;
        }

        bool is_sote(const std::vector<uint8_t> &rom) {
            return rom.size() == kRomSize &&
                std::memcmp(rom.data() + 0x20, kInternalName, sizeof(kInternalName) - 1) == 0;
        }
    }

    bool import_rom(const std::filesystem::path &directory, std::string &message) {
        std::error_code error;
        if (std::filesystem::is_regular_file(directory / kRomFileName, error)) {
            return true;
        }

        for (const char *name : kOtherAcceptedNames) {
            if (std::filesystem::is_regular_file(directory / name, error)) {
                return true;
            }
        }

        bool saw_candidate = false;
        for (const auto &entry : std::filesystem::directory_iterator(directory, error)) {
            if (!entry.is_regular_file(error)) {
                continue;
            }

            const std::filesystem::path &path = entry.path();
            const std::string extension = lowercase_extension(path);
            std::vector<uint8_t> rom;
            if (is_rom_extension(extension)) {
                saw_candidate = true;
                if (!read_file(path, rom)) {
                    continue;
                }
            } else if (extension == ".zip") {
                saw_candidate = true;
                if (!read_zip(path, rom)) {
                    sote::log("rom: %s has no .z64/.v64/.n64 inside", path.filename().string().c_str());
                    continue;
                }
            } else {
                continue;
            }

            if (!to_big_endian(rom) || !is_sote(rom)) {
                sote::log("rom: %s is not Shadows of the Empire", path.filename().string().c_str());
                continue;
            }

            const std::filesystem::path target = directory / kRomFileName;
            std::ofstream out(target, std::ios::binary | std::ios::trunc);
            out.write(reinterpret_cast<const char *>(rom.data()), static_cast<std::streamsize>(rom.size()));
            if (!out) {
                message = "Couldn't save the ROM copy (is the iPhone full?).";
                std::filesystem::remove(target, error);
                return false;
            }

            sote::log("rom: imported %s as %s", path.filename().string().c_str(), kRomFileName);
            return true;
        }

        message = saw_candidate
            ? "The ROM found isn't Shadows of the Empire (USA). Use the USA v1.2 (Rev 2) dump."
            : "No ROM found.";
        return false;
    }
}
