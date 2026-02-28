import Foundation

/// Event types streamed from the Claude CLI via NDJSON.
enum ClaudeEvent {
    case assistantText(String)      // incremental text token
    case toolAction(CratesAction)   // parsed <crates-action> block
    case turnEnd                    // claude finished its turn
    case error(String)              // error message
    case unknown
}

/// Actions Claude can embed as <crates-action>…</crates-action> JSON blocks.
enum CratesAction {
    case getCrate
    case reorderSongs([String])                // ordered list of song titles
    case addSong(title: String, artist: String, bpm: Int?, key: String?, notes: String)
    case setSongNotes(position: Int, notes: String)
    case suggestOrder                          // Claude reasons first, then reorderSongs
}

// MARK: - JSON decoding for CratesAction

struct CratesActionPayload: Decodable {
    let type: String
    // reorder_songs
    let order: [String]?
    // add_song
    let title: String?
    let artist: String?
    let bpm: Int?
    let key: String?
    let notes: String?
    // set_song_notes
    let position: Int?
}

extension CratesAction {
    static func decode(from json: String) -> CratesAction? {
        guard let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(CratesActionPayload.self, from: data) else {
            return nil
        }
        switch payload.type {
        case "get_crate":
            return .getCrate
        case "reorder_songs":
            return .reorderSongs(payload.order ?? [])
        case "add_song":
            return .addSong(
                title: payload.title ?? "",
                artist: payload.artist ?? "",
                bpm: payload.bpm,
                key: payload.key,
                notes: payload.notes ?? ""
            )
        case "set_song_notes":
            return .setSongNotes(
                position: payload.position ?? 1,
                notes: payload.notes ?? ""
            )
        case "suggest_order":
            return .suggestOrder
        default:
            return nil
        }
    }
}
