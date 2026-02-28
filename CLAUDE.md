# Crates — DJ Set Manager

A macOS app for organising DJ setlists with Spotify integration and Claude-powered set advice.

## Architecture

- **CrateState** — data model + JSON persistence (`~/Library/Application Support/Crates/crates.json`)
- **SpotifyState** — token management + 4s polling of `/v1/me/player/currently-playing`
- **SpotifyAuth** — PKCE OAuth helpers + Keychain storage
- **ClaudeProcess** — spawns `claude` CLI subprocess, sends/receives NDJSON
- **ChatViewModel** — conversation state, bridges events to UI
- **ToolExecutor** — parses `<crates-action>` XML blocks, mutates CrateState

## Build

```bash
cd app
xcodegen generate
xcodebuild build -project Crates.xcodeproj -scheme Crates
```

## Spotify Setup (user prerequisite)

1. Go to [developer.spotify.com](https://developer.spotify.com)
2. Create a new app
3. Add `crates://spotify-callback` as a Redirect URI
4. Paste the Client ID into the Spotify setup sheet in the app

## Claude Bridge Protocol

Claude CLI is launched with `--output-format stream-json --input-format stream-json`.

Claude embeds structured actions in XML blocks that ToolExecutor intercepts:

```
<crates-action>{"type":"reorder_songs","order":["Track A","Track B"]}</crates-action>
```

Supported actions: `get_crate`, `reorder_songs`, `add_song`, `set_song_notes`, `suggest_order`

## Key Files

| File | Purpose |
|------|---------|
| `Sources/CrateState.swift` | Data model: Song, Crate, CrateState |
| `Sources/SpotifyAuth.swift` | PKCE helpers + Keychain |
| `Sources/SpotifyState.swift` | Auth flow + polling |
| `Sources/ClaudeProcess.swift` | subprocess lifecycle |
| `Sources/NdjsonParser.swift` | NDJSON line → ClaudeEvent |
| `Sources/ToolExecutor.swift` | ClaudeEvent → CrateState mutation |
| `Sources/PromptInstructions.swift` | Ash system prompt |
