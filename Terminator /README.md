# Terminator

macOS menu bar AI launcher built with SwiftUI + `WKWebView`.

## What It Does

- Runs as a menu bar app (`✶` icon).
- Opens a popover panel below the menu bar icon.
- Global hotkey to open/close: `⌘⇧K`.
- Web tabs for:
  - OpenAI (`chatgpt.com`)
  - Gemini (`gemini.google.com`)
  - Anthropic (`claude.ai`)
- Optional native local chat tab (toggle in Settings).
- Per-provider API key settings.
- Hide providers without keys (or show all via setting).
- Bottom-left resize handle with persisted size.

## Requirements

- macOS 13+
- Xcode Command Line Tools (or Xcode with Swift toolchain)

## Run (Debug)

```bash
swift build
swift run
```

## Build (Release)

```bash
swift build -c release
```

Binary output:

```text
.build/release/Terminator
```

## Settings

Open Settings from the gear icon in the top bar.

- `Enable native Local tab`
- `Show providers without API keys`
- API key fields for OpenAI, Anthropic, Gemini, OpenRouter

Settings modal closes on outside click.

## DMG Packaging (Manual)

Create `.app` bundle and DMG:

```bash
swift build -c release
mkdir -p dist/Terminator.app/Contents/MacOS dist/Terminator.app/Contents/Resources
cp .build/release/Terminator dist/Terminator.app/Contents/MacOS/Terminator
chmod +x dist/Terminator.app/Contents/MacOS/Terminator
```

Create `dist/Terminator.app/Contents/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>Terminator</string>
  <key>CFBundleIdentifier</key><string>com.boski.terminator</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>Terminator</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
```

Create installer DMG with `/Applications` shortcut:

```bash
mkdir -p dist/dmgroot
rm -rf dist/dmgroot/Terminator.app dist/dmgroot/Applications
cp -R dist/Terminator.app dist/dmgroot/Terminator.app
ln -s /Applications dist/dmgroot/Applications
hdiutil create -volname "Terminator" -srcfolder dist/dmgroot -ov -format UDZO Terminator.dmg
```

## Notes

- OAuth/login behavior inside embedded web views can vary by provider.
- Global hotkeys may require macOS permissions depending on environment.
