#!/usr/bin/env python3
"""Fail early when a release tag, plist version or changelog is inconsistent."""
import importlib.util
from pathlib import Path
import plistlib
import sys

root = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("release", root / "scripts/prepare-release.py")
release = importlib.util.module_from_spec(spec); spec.loader.exec_module(release)
info = plistlib.loads((root / "Resources/Info.plist").read_bytes())
version = info["CFBundleShortVersionString"]
tag = sys.argv[1] if len(sys.argv) > 1 else f"v{version}"
release.validate_tag(tag, version)
release.changelog_section((root / "CHANGELOG.md").read_text(), version)
if not str(info["CFBundleVersion"]).isdigit() or int(info["CFBundleVersion"]) < 1:
    raise SystemExit("CFBundleVersion must be a positive build number")
print(f"Validated {tag}; app {version}, build {info['CFBundleVersion']}")
