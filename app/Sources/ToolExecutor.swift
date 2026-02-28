import Foundation

/// Receives CratesActions from Claude and mutates CrateState accordingly.
@MainActor
class ToolExecutor {
    private weak var crateState: CrateState?

    init(crateState: CrateState) {
        self.crateState = crateState
    }

    /// Execute an action and return optional feedback text to inject back to Claude.
    func execute(_ action: CratesAction) -> String? {
        guard let state = crateState else { return nil }

        switch action {
        case .getCrate:
            return serializeActiveCrate(state)

        case .reorderSongs(let titles):
            guard let id = state.activeCrateId else { return "No active crate." }
            state.reorderSongs(in: id, titles: titles)
            return nil

        case .addSong(let title, let artist, let bpm, let key, let notes):
            let song = Song(title: title, artist: artist, bpm: bpm, key: key, notes: notes, source: .manual)
            state.addSong(song)
            return nil

        case .setSongNotes(let position, let notes):
            guard let id = state.activeCrateId,
                  let crateIdx = state.crates.firstIndex(where: { $0.id == id }) else { return nil }
            let idx = position - 1
            guard state.crates[crateIdx].songs.indices.contains(idx) else { return nil }
            var song = state.crates[crateIdx].songs[idx]
            song.notes = notes
            state.updateSong(song, in: id)
            return nil

        case .suggestOrder:
            // Claude will reason first, then follow up with reorder_songs.
            // Return the current crate so Claude has context.
            return serializeActiveCrate(state)
        }
    }

    // MARK: - Serialise

    private func serializeActiveCrate(_ state: CrateState) -> String {
        guard let crate = state.activeCrate else { return "{\"error\":\"No active crate\"}" }
        let songs = crate.songs.enumerated().map { idx, song in
            var obj: [String: Any] = [
                "position": idx + 1,
                "title": song.title,
                "artist": song.artist,
            ]
            if let bpm = song.bpm { obj["bpm"] = bpm }
            if let key = song.key { obj["key"] = key }
            if !song.notes.isEmpty { obj["notes"] = song.notes }
            return obj
        }
        let payload: [String: Any] = [
            "crate": crate.name,
            "songCount": songs.count,
            "songs": songs,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }
}
