#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import tempfile
import unittest

root = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("release", root / "scripts/prepare-release.py")
release = importlib.util.module_from_spec(spec); spec.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    def test_stable_and_prerelease(self):
        self.assertFalse(release.validate_tag("v0.1.2", "0.1.2"))
        self.assertTrue(release.validate_tag("v0.1.2-rc.1", "0.1.2"))

    def test_reject_mismatch_and_unsafe_tags(self):
        for tag in ["v0.2.0", "0.1.2", "v01.1.2", "v0.1.2/../../x", "v0.1.2\n", "v0.1.2;echo x"]:
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                release.validate_tag(tag, "0.1.2")

    def test_changelog_is_version_scoped(self):
        text = "## [Unreleased]\nFuture\n## [0.1.2] - date\nChinese / English\n## [0.1.1]\nOld\n"
        self.assertEqual(release.changelog_section(text, "0.1.2"), "Chinese / English")
        with self.assertRaises(ValueError):
            release.changelog_section(text, "0.1.0")

    def test_release_assets_and_identity(self):
        import hashlib, json, plistlib
        version = plistlib.loads((root / "dist/DoubaoCaret.app/Contents/Info.plist").read_bytes())["CFBundleShortVersionString"]
        with tempfile.TemporaryDirectory() as folder:
            destination, prerelease = release.prepare(f"v{version}", "example/DoubaoCaret", "a" * 40, "adhoc",
                root / "dist/DoubaoCaret.app", root / "dist/DoubaoCaret-macos-universal.zip",
                root / "CHANGELOG.md", Path(folder))
            self.assertFalse(prerelease)
            metadata = json.loads((destination / "build-metadata.json").read_text())
            self.assertEqual(metadata['sha256'], hashlib.sha256((destination / metadata['archive']).read_bytes()).hexdigest())
            self.assertIn('未经 Apple 公证', (destination / "RELEASE-NOTES.md").read_text())
            self.assertIn('Ad-hoc test build', (destination / "RELEASE-NOTES.md").read_text())


if __name__ == '__main__':
    unittest.main()
