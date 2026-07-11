# Gom 🐻

A minimal, fast video player for macOS. Pure AppKit — no SwiftUI.

- MP4 / MOV / M4V play through AVFoundation (`AVPlayerLayer`, hardware-accelerated, near-zero CPU).
- WebM / MKV / AVI and friends fall back to a bundled libmpv engine automatically.
- Borderless look: the video fills the whole window; traffic lights appear on hover.

## Install

```sh
brew tap seongilp/tap
brew install --cask gom
```

Or download the notarized DMG from [Releases](https://github.com/seongilp/gom/releases).

## Keyboard shortcuts

| Key | Action |
|---|---|
| `Space` | Play / Pause |
| `←` / `→` | Seek −5s / +5s |
| `↑` / `↓` | Volume up / down |
| `1` | Resize window to 50% |
| `2` | Resize window to 100% |
| `3` | Resize window to 200% |
| `⌘F` / double-click | Full screen |
| `⌘O` | Open file |

Also supports drag & drop and "Open With" from Finder.

## Build from source

```sh
./scripts/build-app.sh   # → dist/Gom.app (universal binary, codesigned)
```

Requirements: macOS 13+ (Apple Silicon), Xcode command line tools, `brew install mpv dylibbundler`.

## License

MIT
