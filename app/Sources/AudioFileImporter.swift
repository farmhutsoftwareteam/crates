import Foundation
import AVFoundation

struct AudioFileMeta {
    var title:      String
    var artist:     String
    var bpm:        Int?
    var key:        String?    // as tagged (TKEY — e.g. "Am", "F#m", or Camelot if pool uses it)
    var durationMs: Int?
}

enum AudioFileImporter {

    /// Reads ID3 / iTunes / common metadata from an audio file using AVFoundation.
    /// No external tools required — works with MP3, M4A, AIFF, FLAC, WAV.
    static func read(url: URL) async -> AudioFileMeta {
        var title      = url.deletingPathExtension().lastPathComponent
        var artist     = ""
        var bpm:        Int?    = nil
        var key:        String? = nil
        var durationMs: Int?    = nil

        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])

        // Duration
        if let dur = try? await asset.load(.duration), dur.seconds > 0 {
            durationMs = Int(dur.seconds * 1000)
        }

        // All metadata (spans ID3, iTunes, QuickTime, Vorbis, etc.)
        let all = (try? await asset.load(.metadata)) ?? []

        for item in all {
            let raw = item.identifier?.rawValue ?? ""
            guard let value = try? await item.load(.stringValue), !value.isEmpty else { continue }

            // ── Common (cross-format) ───────────────────────────
            switch item.commonKey {
            case .commonKeyTitle  where !value.isEmpty: title  = value
            case .commonKeyArtist where !value.isEmpty: artist = value
            default: break
            }

            // ── ID3 (MP3) ───────────────────────────────────────
            // Identifiers: "id3/TXXX", "id3/TBPM", etc.
            switch raw {
            case "id3/TBPM":
                if let n = Int(value) { bpm = n }
            case "id3/TKEY":
                key = value
            case "id3/TPE1" where artist.isEmpty:
                artist = value
            case "id3/TIT2" where title == url.deletingPathExtension().lastPathComponent:
                title = value
            default: break
            }

            // ── iTunes / M4A ────────────────────────────────────
            // "itsk/tmpo" = BPM, stored as number
            if raw == "itsk/tmpo" {
                if let n = Int(value), bpm == nil { bpm = n }
            }
        }

        // Numeric fallback for iTunes BPM (may come as NSNumber not String)
        if bpm == nil {
            let numericItems = all.filter { $0.identifier?.rawValue == "itsk/tmpo" }
            if let numVal = try? await numericItems.first?.load(.value) as? Int {
                bpm = numVal
            }
        }

        return AudioFileMeta(title: title, artist: artist, bpm: bpm, key: key, durationMs: durationMs)
    }
}
