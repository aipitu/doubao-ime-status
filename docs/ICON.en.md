# Application icon

[中文](ICON.md) | **English**

- Source: `Resources/AppIcon-source.png`, preserving generated artwork and transparency.
- Packaged icon: `Resources/AppIcon.icns`, with 11 PNG representations covering 16–1024 px and Retina slots.
- `CFBundleIconFile` references the ICNS; packaging copies and signs it as an app resource.
- Regenerate format/sizes with `python3 scripts/make-icon.py` (Pillow required only for regeneration).
- The artwork was generated with the built-in image-generation tool, not copied from Doubao's official logo. The complete English generation prompt is preserved in [the source notes](ICON.md).
