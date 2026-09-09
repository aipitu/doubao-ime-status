#!/usr/bin/env python3
"""Package the generated artwork as multi-resolution PNG-backed macOS ICNS.

Only format/size conversion is performed; the generated artwork is unchanged.
Pillow is needed only when regenerating the checked-in AppIcon.icns.
"""
from pathlib import Path
from io import BytesIO
import struct
from PIL import Image

root = Path(__file__).resolve().parent.parent
with Image.open(root / "Resources/AppIcon-source.png") as original:
    assert original.width == original.height
    original = original.convert("RGBA")
    assert original.getextrema()[3][0] == 0, "icon must have transparent outer margins"
    chunks = []
    # Standard sizes plus explicit Retina slots (16@2x, 32@2x, 128@2x, 256@2x).
    for tag, pixels in [(b"icp4", 16), (b"icp5", 32), (b"icp6", 64),
                        (b"ic07", 128), (b"ic08", 256), (b"ic09", 512),
                        (b"ic10", 1024), (b"ic11", 32), (b"ic12", 64),
                        (b"ic13", 256), (b"ic14", 512)]:
        output = BytesIO()
        original.resize((pixels, pixels), Image.Resampling.LANCZOS).save(output, format="PNG")
        content = output.getvalue()
        chunks.append(tag + struct.pack(">I", len(content) + 8) + content)
    content = b"".join(chunks)
    path = root / "Resources/AppIcon.icns"
    path.write_bytes(b"icns" + struct.pack(">I", len(content) + 8) + content)
    print(f"Packaged {path}: {len(chunks)} resolutions, {path.stat().st_size} bytes")
