#!/usr/bin/env python3
"""Package a real Mach-O app, preserving executable permission in the ZIP."""
import pathlib
import plistlib
import shutil
import struct
import sys
import zipfile


def archive_app(destination):
    archive = destination.parent / "DoubaoCaret-macos-universal.zip"
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as z:
        for path in sorted(destination.rglob("*")):
            z.write(path, path.relative_to(destination.parent))
    print(f"Packaged {destination} and {archive}")


def universal(paths):
    slices = [pathlib.Path(p).read_bytes() for p in paths]
    table = bytearray(struct.pack(">II", 0xCAFEBABE, len(slices)))
    output = bytearray(16384)
    offset = len(output)
    for binary in slices:
        magic, cpu, subtype = struct.unpack_from("<III", binary)
        if magic != 0xFEEDFACF:
            raise ValueError("Expected a 64-bit Mach-O executable")
        table += struct.pack(">IIIII", cpu, subtype, offset, len(binary), 14)
        output += binary
        output += bytes((-len(output)) % 16384)
        offset = len(output)
    output[:len(table)] = table
    return output


if __name__ == "__main__":
    args = sys.argv[1:]
    if args[0] == "--zip-only":
        archive_app(pathlib.Path(args[1])); sys.exit(0)
    if args[0] == "--universal":
        binary = universal(args[1:3]); destination = pathlib.Path(args[3])
    else:
        binary = pathlib.Path(args[0]).read_bytes(); destination = pathlib.Path(args[1])
    root = pathlib.Path(__file__).resolve().parent.parent
    macos = destination / "Contents/MacOS"
    resources = destination / "Contents/Resources"
    macos.mkdir(parents=True, exist_ok=True); resources.mkdir(parents=True, exist_ok=True)
    executable = macos / "DoubaoCaret"
    executable.write_bytes(binary); executable.chmod(0o755)
    plist = plistlib.loads((root / "Resources/Info.plist").read_bytes())
    (destination / "Contents/Info.plist").write_bytes(plistlib.dumps(plist))
    (destination / "Contents/PkgInfo").write_text("APPL????")
    shutil.copy2(root / "Resources/AppIcon.icns", resources / "AppIcon.icns")
    shutil.copytree(root / "THIRD_PARTY_LICENSES", resources / "Licenses", dirs_exist_ok=True)
    if (root / "LICENSE").exists():
        shutil.copy2(root / "LICENSE", resources / "LICENSE.txt")
    archive_app(destination)
