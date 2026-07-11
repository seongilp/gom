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
| `←` / `→` | Seek ±5s (`⇧`: ±30s) |
| `↑` / `↓` | Volume |
| Scroll | Volume · horizontal scroll: seek |
| `,` / `.` | Frame step (while paused) |
| `[` / `]` / `\` | Speed −/+ 0.25× / reset |
| `Home` / `End` | Jump to start / end |
| `1` `2` `3` | Window 50% / 100% / 200% |
| `⌘←` / `⌘→` | Previous / next file in folder (or queue) |
| `L` | Loop |
| `M` | Mute |
| `S` | Snapshot (PNG saved next to the video) |
| `C` | Subtitles on/off |
| `T` | Always on top |
| `V` | Media info + live stats (fps, bitrate, hwdec…) |
| `?` | Keyboard shortcut help |
| `⌘F` / double-click | Full screen |
| `⌘O` | Open file(s) |

More built-ins:

- **Resume playback** — reopening a file continues where you left off.
- **Open Recent** menu (last 10 files).
- **Drop multiple files** to build a play queue; playback advances automatically.
- **Subtitles** — a matching `.srt`/`.ass`/`.vtt` next to the video loads automatically (played via mpv); drop a subtitle file onto the window to load it manually.
- **Media keys / Now Playing** — play/pause and skip from the keyboard media keys, AirPods, or Control Center.
- The display won't sleep during playback, and the cursor hides when idle.
- Pausing (or moving the mouse) shows the seek bar HUD; it auto-hides during playback.

Also supports drag & drop and "Open With" from Finder.

## Build from source

```sh
./scripts/build-app.sh   # → dist/Gom.app (universal binary, codesigned)
```

Requirements: macOS 13+ (Apple Silicon), Xcode command line tools, `brew install mpv dylibbundler`.

## License

MIT
