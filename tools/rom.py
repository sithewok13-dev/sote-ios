#!/usr/bin/env python3
"""Finds the Shadows of the Empire ROM in what the player downloaded, puts it in the
.z64 byte order and checks it's the USA v1.2 (Rev 2) version the port is made for.
The builder (github.com/sithewok13-dev/sote-builder) runs it; the app checks the
same thing on the phone.

  python3 tools/rom.py <downloaded file> <out.z64>

The download can be the ROM itself (.z64, .v64 or .n64, any name) or an archive with
it inside (.zip natively; .7z, .rar, .gz and others through 7-Zip, `7zz` or `7z`).
Every problem is reported in plain words, as a GitHub Actions error when run there.
Only Python's standard library is needed.
"""
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile

ROM_SHA256 = "e7085e013123537f34e0edec8801318016da4dbac424172d6dc5f3b67d98642c"  # the No-Intro dump
# SotE-Recomp also accepts a widely mirrored copy that differs in one byte outside
# the game's code and data (tools/prepare_recomp_rom.py, src/main.cpp).
ACCEPTED_SHA256 = {ROM_SHA256, "2802bf4135842f7c8d254349ed7ac2641f6d7ff45e9d2d01304e1455706dd103"}
MAX_SIZE = 256 * 1024 * 1024  # bigger than any N64 ROM

# The first four bytes of an N64 ROM in each byte order.
Z64 = bytes.fromhex("80371240")  # big-endian, the native order
V64 = bytes.fromhex("37804012")  # 16-bit byte-swapped
N64 = bytes.fromhex("40123780")  # 32-bit little-endian
ORDERS = {Z64: ".z64", V64: ".v64", N64: ".n64"}

REGIONS = {"E": "US (NTSC)", "P": "European (PAL)", "J": "Japanese", "D": "German", "F": "French",
           "U": "Australian", "X": "European (PAL)", "Y": "European (PAL)"}

HOW_TO_SHARE = ("Use a link anyone can open: in Google Drive, the file's ⋮ > Share > General access: "
                "Anyone with the link.")


def fail(message):
    prefix = "::error::" if os.environ.get("GITHUB_ACTIONS") == "true" else "error: "
    print(prefix + message, flush=True)
    sys.exit(1)


def head(path, n=4):
    with open(path, "rb") as f:
        return f.read(n)


def to_z64(data):
    """The ROM in the .z64 byte order, and the order it came in."""
    magic = bytes(data[:4])
    data = data[:len(data) - len(data) % 4]
    if magic == Z64:
        return bytes(data), ".z64"
    out = bytearray(data)
    if magic == V64:
        out[0::2], out[1::2] = data[1::2], data[0::2]
        return bytes(out), ".v64"
    if magic == N64:
        out[0::4], out[1::4], out[2::4], out[3::4] = data[3::4], data[2::4], data[1::4], data[0::4]
        return bytes(out), ".n64"
    return None, None


def is_rom(path):
    try:
        size = os.path.getsize(path)
        return 1024 * 1024 <= size <= MAX_SIZE and head(path) in ORDERS
    except OSError:
        return False


def is_archive(path):
    start = head(path, 8)
    return (start.startswith(b"PK\x03\x04") or start.startswith(b"7z\xbc\xaf\x27\x1c")
            or start.startswith(b"Rar!") or start.startswith(b"\x1f\x8b")
            or start.startswith(b"\xfd7zXZ\x00") or start.startswith(b"BZh"))


def seven_zip():
    for name in (os.environ.get("Z"), "7zz", "7z", "7za"):
        if name and shutil.which(name):
            return shutil.which(name)
    return None


def unpack(path, into):
    """Unpacks an archive into `into`; zips natively, anything else with 7-Zip."""
    if zipfile.is_zipfile(path):
        try:
            with zipfile.ZipFile(path) as z:
                for info in z.infolist():
                    # only names inside `into` (no absolute paths or ..)
                    target = os.path.realpath(os.path.join(into, info.filename))
                    if not target.startswith(os.path.realpath(into) + os.sep):
                        continue
                    z.extract(info, into)
            return True
        except (zipfile.BadZipFile, NotImplementedError, RuntimeError, OSError):
            pass  # an encrypted or unusual zip: let 7-Zip try
    tool = seven_zip()
    if not tool:
        fail("Could not unpack the download (7-Zip is missing on the build machine). Share the ROM itself "
             "(.z64, .n64 or .v64) or a .zip of it instead.")
    result = subprocess.run([tool, "x", "-y", "-p", "-o" + into, path],
                            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    return result.returncode == 0


def find_roms(root):
    found = []
    for folder, dirs, names in os.walk(root):
        dirs.sort()
        for name in sorted(names):
            path = os.path.join(folder, name)
            if is_rom(path):
                found.append(path)
    return found


def describe(rom):
    """(game code, region letter, title) from the ROM's header (.z64 order)."""
    title = rom[0x20:0x34].decode("ascii", "replace").strip(" \0")
    code = rom[0x3B:0x3F].decode("ascii", "replace")
    return code, code[3:4], title


def check(rom):
    sha = hashlib.sha256(rom).hexdigest()
    code, region, title = describe(rom)
    if sha in ACCEPTED_SHA256:
        return
    if code[1:3] != "SW":
        fail(f"That's not Shadows of the Empire: the ROM says it's \"{title or 'unknown'}\". "
             "Share your Star Wars: Shadows of the Empire ROM instead.")
    if region != "E":
        name = REGIONS.get(region, f"a different ({region})")
        fail(f"That's the {name} version of Shadows of the Empire. The port only works with the USA "
             "version 1.2 (Rev 2), so you need a ROM dumped from that US cartridge.")
    revision = rom[0x3F]
    if revision != 2:
        fail(f"That's the USA Shadows of the Empire, but version 1.{revision} (Rev {revision}). The port only "
             "works with version 1.2 (Rev 2).")
    fail("That's the USA Shadows of the Empire v1.2, but not an exact copy of the cartridge. "
         "It may be damaged, cut short, padded, or patched (a hack, translation or fan fix). "
         "Dump your cartridge again or use an unmodified dump "
         f"(its SHA-256 is {sha}; the right one is {ROM_SHA256}).")


def load(download, out):
    """[(path, rom in .z64 order, order it came in)] for every ROM in the download."""
    if is_rom(download):
        return [(download,) + to_z64(open(download, "rb").read())]
    if not is_archive(download):
        size = os.path.getsize(download)
        if size > MAX_SIZE:
            fail(f"The download is {size // (1024 * 1024)} MB: too big to be an N64 ROM. Share just your Shadows "
                 "of the Empire ROM, or a .zip or .7z with only it inside.")
        fail("That file isn't an N64 ROM or an archive with one inside. Share your Shadows of the Empire ROM "
             "(.z64, .n64 or .v64), or a .zip or .7z with it inside.")
    work = tempfile.mkdtemp(prefix="rom-", dir=os.path.dirname(os.path.abspath(out)))
    try:
        if not unpack(download, work):
            fail("Could not unpack the download. It should be the ROM (.z64, .n64 or .v64) or a "
                 ".zip or .7z with it inside, without a password.")
        candidates = find_roms(work)
        if not candidates:
            # an archive inside the archive (a .zip in a .7z, say): one level more
            for folder, _, names in os.walk(work):
                for name in sorted(names):
                    path = os.path.join(folder, name)
                    if is_archive(path):
                        unpack(path, tempfile.mkdtemp(prefix="inner-", dir=work))
            candidates = find_roms(work)
        if not candidates:
            fail("There's no N64 ROM in the archive you shared. Put your Shadows of the Empire ROM "
                 "(.z64, .n64 or .v64) in it, or share the ROM itself.")
        return [(path,) + to_z64(open(path, "rb").read()) for path in candidates]
    finally:
        shutil.rmtree(work, ignore_errors=True)


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    download, out = sys.argv[1], sys.argv[2]
    if not os.path.isfile(download) or os.path.getsize(download) == 0:
        fail("The download is empty. Check that the link opens your ROM without signing in. " + HOW_TO_SHARE)
    start = head(download, 512).lower()
    if b"<html" in start or b"<!doctype html" in start:
        fail("The link gave a web page, not your ROM. " + HOW_TO_SHARE)

    roms = load(download, out)
    # Several ROMs in one archive: the right one if it's there, else the first SotE, else the first.
    roms.sort(key=lambda r: (hashlib.sha256(r[1]).hexdigest() not in ACCEPTED_SHA256, describe(r[1])[0][1:3] != "SW"))
    _, rom, came_as = roms[0]
    check(rom)
    with open(out, "wb") as f:
        f.write(rom)
    how = "already in the .z64 byte order" if came_as == ".z64" else f"converted from the {came_as} byte order to .z64"
    print(f"Your ROM: Shadows of the Empire (USA v1.2), a version the port accepts (SHA-256 {hashlib.sha256(rom).hexdigest()}), {how}.")


if __name__ == "__main__":
    main()
