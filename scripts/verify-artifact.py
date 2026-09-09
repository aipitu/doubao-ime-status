#!/usr/bin/env python3
"""Verify packaging plus Mach-O load commands without executing Darwin code."""
import hashlib
import pathlib
import plistlib
import struct
import sys
import zipfile


def verify_signature(binary, start, amount, app):
    signature = binary[start:start+amount]
    magic, length, count = struct.unpack_from(">III", signature)
    assert magic == 0xFADE0CC0 and length <= len(signature)
    blobs = {}
    for index in range(count):
        slot, offset = struct.unpack_from(">II", signature, 12 + index * 8)
        blob_size = struct.unpack_from(">I", signature, offset + 4)[0]
        assert offset + blob_size <= length
        blobs[slot] = signature[offset:offset+blob_size]
    cd = blobs[0]
    (magic, length, version, flags, hash_offset, identifier_offset,
     special_count, code_count, code_limit) = struct.unpack_from(">9I", cd)
    assert magic == 0xFADE0C02
    hash_size, hash_type, platform, page_log = struct.unpack_from(">4B", cd, 36)
    algorithm = {1: "sha1", 2: "sha256", 3: "sha256", 4: "sha384"}[hash_type]
    digest = lambda content: hashlib.new(algorithm, content).digest()[:hash_size]
    assert cd[identifier_offset:].split(b"\0")[0] == b"local.doubao-caret"
    assert code_limit <= start
    page_size = 1 << page_log
    assert code_count == (code_limit + page_size - 1) // page_size
    for index in range(code_count):
        content = binary[index*page_size:min((index+1)*page_size, code_limit)]
        expected = cd[hash_offset+index*hash_size:hash_offset+(index+1)*hash_size]
        assert digest(content) == expected, f"invalid signed code page {index}"
    sealed = {1: (app / "Contents/Info.plist").read_bytes(),
              3: (app / "Contents/_CodeSignature/CodeResources").read_bytes()}
    for index in range(1, special_count + 1):
        expected = cd[hash_offset-index*hash_size:hash_offset-(index-1)*hash_size]
        if not any(expected):
            continue
        content = sealed.get(index, blobs.get(index))
        assert content is not None, f"missing special signature slot {index}"
        assert digest(content) == expected, f"invalid signed special slot {index}"

app = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "dist/DoubaoCaret.app")
info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
assert info["LSUIElement"] is True
assert info["CFBundleIdentifier"] == "local.doubao-caret"
assert info["LSMinimumSystemVersion"] == "13.0"
exe = app / "Contents/MacOS" / info["CFBundleExecutable"]
assert exe.stat().st_mode & 0o111, "missing executable permission"
data = exe.read_bytes()
magic, count = struct.unpack_from(">II", data)
assert magic == 0xCAFEBABE and count == 2, "not a universal Mach-O"
architectures = set()
for index in range(count):
    cpu, subtype, offset, size, align = struct.unpack_from(">IIIII", data, 8 + index * 20)
    assert offset % (1 << align) == 0 and offset + size <= len(data)
    binary = data[offset:offset+size]
    mh, actual_cpu, actual_subtype, kind, ncmds, commands_size, flags, reserved = struct.unpack_from("<8I", binary)
    assert mh == 0xFEEDFACF and kind == 2
    assert (cpu, subtype) == (actual_cpu, actual_subtype)
    arch = {0x100000C: "arm64", 0x1000007: "x86_64"}[cpu]
    architectures.add(arch)
    position = 32
    has_signature = has_entry = has_version = False
    libraries = []
    for _ in range(ncmds):
        cmd, length = struct.unpack_from("<II", binary, position)
        assert length >= 8 and position + length <= 32 + commands_size
        if cmd == 0x32:  # LC_BUILD_VERSION
            platform, minimum, sdk = struct.unpack_from("<III", binary, position + 8)
            assert platform == 1 and minimum == 0x000D0000, "wrong deployment target"
            has_version = True
        elif cmd == 0x1D:  # LC_CODE_SIGNATURE
            start, amount = struct.unpack_from("<II", binary, position + 8)
            assert start + amount <= len(binary) and amount > 0
            assert struct.unpack_from(">I", binary, start)[0] == 0xFADE0CC0
            verify_signature(binary, start, amount, app)
            has_signature = True
        elif cmd == 0x80000028:  # LC_MAIN
            has_entry = True
        elif cmd in (0xC, 0x80000018, 0x8000001F):
            relative = struct.unpack_from("<I", binary, position + 8)[0]
            name = binary[position+relative:position+length].split(b"\0")[0].decode()
            assert name.startswith(("/System/Library/", "/usr/lib/")), f"non-system dependency: {name}"
            libraries.append(name)
        position += length
    assert position == 32 + commands_size
    assert has_signature and has_entry and has_version
    assert any("AppKit.framework" in name for name in libraries)
    print(f"PASS {arch}: Mach-O, macOS 13.0+, entry point, code-page/plist/resource signature hashes, {len(libraries)} system dependencies")
assert architectures == {"arm64", "x86_64"}
assert (app / "Contents/Resources/Licenses/input-indicator.txt").exists()
assert info.get("CFBundleIconFile") == "AppIcon.icns"
icon = (app / "Contents/Resources/AppIcon.icns").read_bytes()
assert icon[:4] == b"icns" and struct.unpack_from(">I", icon, 4)[0] == len(icon)
position = 8
icon_sizes = set()
while position < len(icon):
    kind, length = struct.unpack_from(">4sI", icon, position)
    assert length > 32 and position + length <= len(icon)
    png = icon[position+8:position+length]
    assert png[:8] == b"\x89PNG\r\n\x1a\n"
    width, height = struct.unpack_from(">II", png, 16)
    assert width == height and png[25] == 6, "icon must be RGBA"
    icon_sizes.add(width)
    position += length
assert position == len(icon) and icon_sizes == {16, 32, 64, 128, 256, 512, 1024}
print("PASS app icon reference, ICNS container and 16–1024 px RGBA representations")
resources = plistlib.loads((app / "Contents/_CodeSignature/CodeResources").read_bytes())
for relative, entry in resources.get("files2", {}).items():
    if "hash2" in entry:
        assert hashlib.sha256((app / "Contents" / relative).read_bytes()).digest() == entry["hash2"]
print("PASS sealed resource contents")
archive = app.parent / "DoubaoCaret-macos-universal.zip"
if archive.exists():
    with zipfile.ZipFile(archive) as z:
        member = z.getinfo(f"{app.name}/Contents/MacOS/DoubaoCaret")
        assert member.external_attr >> 16 & 0o111
        assert z.read(member) == data, "ZIP contains a stale/unsigned executable"
        assert z.testzip() is None
    print(f"PASS ZIP CRC, executable permissions and packaged bytes")
print(f"PASS LSUIElement, app metadata and third-party license")
print(f"SHA256 executable: {hashlib.sha256(data).hexdigest()}")
