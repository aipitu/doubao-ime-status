#!/usr/bin/env python3
"""Validate a tag against the built app and stage checksummed release assets."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import zipfile

ROOT = Path(__file__).resolve().parent.parent
TAG = re.compile(r"v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-([0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*))?\Z")


def validate_tag(tag, version):
    match = TAG.fullmatch(tag)
    if not match:
        raise ValueError("Expected vMAJOR.MINOR.PATCH or vMAJOR.MINOR.PATCH-rc.1")
    core = ".".join(match.group(i) for i in (1, 2, 3))
    if core != version:
        raise ValueError(f"Tag {tag} does not match CFBundleShortVersionString {version}")
    return match.group(4) is not None


def changelog_section(text, version):
    match = re.search(r"^## \[" + re.escape(version) + r"\][^\n]*\n(.*?)(?=^## \[|\Z)", text, re.M | re.S)
    if not match or not match.group(1).strip():
        raise ValueError(f"CHANGELOG.md needs a nonempty [{version}] section")
    return match.group(1).strip()


def prepare(tag, repo, commit, signing, app, archive, changelog, output):
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repo):
        raise ValueError("Expected owner/repository")
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError("Expected a full 40-character commit SHA")
    if signing not in ("adhoc", "developer-id-notarized"):
        raise ValueError("Unknown signing mode")
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != "local.doubao-caret":
        raise ValueError("Unexpected app identity")
    version = info["CFBundleShortVersionString"]
    prerelease = validate_tag(tag, version)
    changes = changelog_section(changelog.read_text(), version)
    # Ensure the uploaded archive is the final (possibly stapled) bundle.
    with zipfile.ZipFile(archive) as z:
        if z.testzip():
            raise ValueError("ZIP CRC failure")
        for relative in ("Contents/Info.plist", "Contents/MacOS/DoubaoCaret",
                         "Contents/Resources/AppIcon.icns", "Contents/_CodeSignature/CodeResources"):
            if z.read(f"DoubaoCaret.app/{relative}") != (app / relative).read_bytes():
                raise ValueError(f"Stale archive: {relative}")
    folder = output / tag
    folder.mkdir(parents=True, exist_ok=True)
    name = f"DoubaoCaret-{tag}-macos-universal.zip"
    shutil.copy2(archive, folder / name)
    digest = hashlib.sha256((folder / name).read_bytes()).hexdigest()
    metadata = {"version": version, "tag": tag, "repository": repo, "commit": commit,
                "architectures": ["arm64", "x86_64"], "minimum_macos": "13.0",
                "signing": signing, "archive": name, "sha256": digest}
    (folder / "build-metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
    metadata_digest = hashlib.sha256((folder / "build-metadata.json").read_bytes()).hexdigest()
    (folder / "SHA256SUMS").write_text(f"{digest}  {name}\n{metadata_digest}  build-metadata.json\n")
    identity = ("Developer ID signed and Apple notarized / Developer ID 签名并经 Apple 公证"
                if signing == "developer-id-notarized" else
                "Ad-hoc test build, not Apple notarized / 临时签名测试包，未经 Apple 公证")
    notes = f"""# DoubaoCaret {tag}

macOS 13+ · Apple Silicon + Intel · {identity}

## 安装 / Install

下载 `{name}`，解压后将 `DoubaoCaret.app` 移入 `/Applications`。启动后在「权限设置与更新修复」中允许辅助功能和输入监控。

Download `{name}`, unzip it, and move `DoubaoCaret.app` into `/Applications`. Open the app and grant Accessibility and Input Monitoring through its permission window.

测试包若被拦截，在系统设置 → 隐私与安全性中选择「仍要打开」。Ad-hoc 更新可能需要重新授权；固定安装路径本身不能解决签名变化。

For blocked test builds, use System Settings → Privacy & Security → Open Anyway. Ad-hoc updates may require reauthorization; keeping the same path alone does not preserve signing identity.

## 校验 / Verify

下载 ZIP 和 `SHA256SUMS` 到同一目录，然后执行 / Download the ZIP and `SHA256SUMS` to the same directory, then run:

```bash
shasum -a 256 --ignore-missing -c SHA256SUMS
```

## 更新内容 / Changes

{changes}

## 已知限制 / Known limitations

Caret 支持取决于目标应用；无可靠位置时跟随鼠标。豆包状态来自外部可观测信号，无证据时显示 `?`。自动构建和启动测试不验证真实输入法准确率、caret 覆盖或 CPU。

Caret support depends on the target app and falls back to the mouse. Doubao mode is inferred from observable signals; unknown state shows `?`. Build and startup tests do not verify real IME accuracy, caret coverage, or CPU usage.

Source / 源码: https://github.com/{repo}/tree/{commit}
"""
    (folder / "RELEASE-NOTES.md").write_text(notes)
    return folder, prerelease


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--signing", choices=["adhoc", "developer-id-notarized"], default="adhoc")
    args = parser.parse_args()
    folder, prerelease = prepare(args.tag, args.repository, args.commit, args.signing,
        ROOT / "dist/DoubaoCaret.app", ROOT / "dist/DoubaoCaret-macos-universal.zip",
        ROOT / "CHANGELOG.md", ROOT / "dist/release")
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a") as stream:
            stream.write(f"tag={args.tag}\nasset_dir={folder}\nprerelease={str(prerelease).lower()}\n")
    print(f"Prepared {folder}")


if __name__ == "__main__":
    main()
