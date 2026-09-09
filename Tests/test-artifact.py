#!/usr/bin/env python3
"""The artifact verifier must reject modified code, metadata and resources."""
import pathlib
import plistlib
import shutil
import struct
import subprocess
import sys
import tempfile

root = pathlib.Path(__file__).resolve().parent.parent
for kind in ("code", "metadata", "resource", "icon"):
    with tempfile.TemporaryDirectory(prefix="doubao-signature-test-") as directory:
        app = pathlib.Path(directory) / "DoubaoCaret.app"
        shutil.copytree(root / "dist/DoubaoCaret.app", app)
        if kind == "code":
            executable = app / "Contents/MacOS/DoubaoCaret"
            data = bytearray(executable.read_bytes())
            offset = struct.unpack_from(">I", data, 16)[0]
            data[offset + 8192] ^= 1
            executable.write_bytes(data)
        elif kind == "metadata":
            plist = app / "Contents/Info.plist"
            info = plistlib.loads(plist.read_bytes()); info["CFBundleName"] = "Tampered"
            plist.write_bytes(plistlib.dumps(info))
        elif kind == "icon":
            icon = app / "Contents/Resources/AppIcon.icns"
            data = bytearray(icon.read_bytes()); data[-1] ^= 1; icon.write_bytes(data)
        else:
            with (app / "Contents/Resources/Licenses/input-indicator.txt").open("a") as file:
                file.write("tampered")
        result = subprocess.run([sys.executable, str(root / "scripts/verify-artifact.py"), str(app)],
                                capture_output=True, text=True)
        assert result.returncode != 0, f"verifier accepted modified {kind}"
        assert "AssertionError" in result.stderr, result.stderr
        print(f"PASS rejects modified {kind}")
