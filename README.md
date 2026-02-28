# Crates 🎛️

A minimal, dark macOS app for organising DJ sets — with AI-powered track analysis built in.

![macOS](https://img.shields.io/badge/macOS-13%2B-black?style=flat-square)
![Swift](https://img.shields.io/badge/Swift-5.9-orange?style=flat-square)
![Claude](https://img.shields.io/badge/Powered%20by-Claude-blueviolet?style=flat-square)

---

## What it does

Crates lets you build and manage DJ set lists. Import a folder of tracks, and it automatically analyses every song using Claude AI — returning BPM, Camelot key, energy score, and danceability without you touching anything.

**Key features:**
- **Folder import** — drag a folder onto the sidebar or use ⌘O. Songs appear instantly from ID3 tags, then Claude analyses each one in the background
- **AI track analysis** — right-click any crate → *Re-analyse Set* to run Claude on every track (BPM, Camelot key, energy 0–10, danceability 0–10)
- **Ash** — an embedded AI DJ advisor powered by Claude. Ask it to reorder your set, suggest transitions, analyse the energy flow
- **Now Playing bar** — reads the currently playing track from any app via `nowplaying-cli` and lets you save it directly to a crate
- **Energy bars** — 5-segment VU-meter style indicators per track, coloured by energy level
- **DJ pool search** — one-click search on Beatsource, Beatport, Traxsource, SoundCloud from any track's hover menu
- **SoundCloud download** — downloads tracks via `yt-dlp` into `~/Music/Crates/`
- **Downloads watcher** — automatically detects new audio files in `~/Downloads` (ZipDJ, BPM Supreme, DJcity, etc.) and offers one-click import with tags pre-read
- **Drag to reorder** — drag tracks within a set to plan your flow
- **Persistent** — sets save automatically to `~/Library/Application Support/Crates/crates.json`

---

## Screenshots

> *Black Booth aesthetic — near-black background, warm amber accent*

---

## Requirements

- macOS 13+
- [Xcode 15+](https://developer.apple.com/xcode/)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`
- [Claude Code CLI](https://claude.ai/code) — must be installed and authenticated
- [nowplaying-cli](https://github.com/musa11971/nowplaying-cli) — `brew install nowplaying-cli` (optional, for Now Playing bar)
- [yt-dlp](https://github.com/yt-dlp/yt-dlp) — `brew install yt-dlp` (optional, for SoundCloud download)

---

## Build & run

```bash
git clone https://github.com/YOUR_USERNAME/crates.git
cd crates/app
xcodegen generate
xcodebuild build -project Crates.xcodeproj -scheme Crates
open ~/Library/Developer/Xcode/DerivedData/Crates-*/Build/Products/Debug/Crates.app
```

Or open `app/Crates.xcodeproj` in Xcode and hit ▶.

---

## How the AI analysis works

When you import a folder or trigger *Re-analyse Set*, Crates sends a one-shot prompt to the Claude CLI for each track:

```
For "Falling" by Elderbrook & Shimza, provide DJ metadata:
{"bpm": 124, "camelot_key": "9A", "musical_key": "Bm", "energy": 7.5, "danceability": 8.0}
```

Claude uses its training data and web search to return accurate results for most released tracks. Up to 4 queries run concurrently. Results stream into the UI as they arrive — energy bars fill in, keys populate, all without blocking the app.

**Ash** (the chat panel) uses Claude's streaming API to give set advice, suggest track order, spot energy dips, and answer questions about your music.

---

## Project structure

```
crates/
├── app/
│   ├── Sources/
│   │   ├── CratesApp.swift        # @main entry, app lifecycle
│   │   ├── CrateState.swift       # Data model, persistence, analysis orchestration
│   │   ├── ContentView.swift      # Root two-column layout
│   │   ├── CratesSidebar.swift    # Crate list, folder import, drag-drop
│   │   ├── SongListView.swift     # Track list with column headers
│   │   ├── SongCard.swift         # Individual track row, energy bar, hover actions
│   │   ├── NowPlayingBar.swift    # System media integration via nowplaying-cli
│   │   ├── ChatView.swift         # Ash AI advisor panel
│   │   ├── ChatViewModel.swift    # Claude streaming bridge
│   │   ├── ClaudeProcess.swift    # Claude CLI subprocess management
│   │   ├── BPMService.swift       # Claude one-shot analysis + DJ pool search
│   │   ├── TrackAnalyzer.swift    # Python/librosa analysis (optional deep path)
│   │   ├── AudioFileImporter.swift # AVFoundation ID3 tag reading
│   │   ├── FolderWatcher.swift    # ~/Downloads file system watcher
│   │   ├── ImportBanner.swift     # Slide-in new download notification
│   │   ├── Theme.swift            # Design tokens, TrackAvatar, button styles
│   │   └── ...
│   ├── Resources/
│   │   ├── analyze_tracks.py      # librosa + mutagen audio analysis script
│   │   └── Crates.entitlements
│   └── project.yml                # XcodeGen config
└── CLAUDE.md                      # Claude Code instructions for this project
```

---

## Tech stack

| Layer | Technology |
|-------|-----------|
| UI | SwiftUI (macOS 13+) |
| AI analysis | Claude CLI (`claude -p` one-shot) |
| AI chat | Claude CLI (stream-json mode) |
| Now Playing | `nowplaying-cli` + macOS Media Remote |
| Audio metadata | AVFoundation (ID3, iTunes, Vorbis tags) |
| Deep audio analysis | Python + librosa 0.11 + mutagen (optional) |
| Downloads | `yt-dlp` (SoundCloud via `scsearch1:`) |
| Persistence | JSON → `~/Library/Application Support/Crates/` |
| Project gen | XcodeGen |

---

## Claude Code integration

This project was built entirely with [Claude Code](https://claude.ai/code). The `CLAUDE.md` file at the root contains project-specific instructions for the Claude Code agent.

The app itself embeds Claude as a runtime dependency — it spawns the `claude` CLI as a subprocess for both the Ash chat advisor and track analysis. The `CLAUDECODE` environment variable is stripped before spawning to allow nested sessions.

---

## License

MIT
