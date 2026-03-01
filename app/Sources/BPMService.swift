import Foundation

/// Looks up BPM, key, energy and danceability for a track using Claude.
enum BPMService {

    struct Metadata {
        let bpm: Int?
        let key: String?        // Camelot notation e.g. "8A"
        let musicalKey: String? // Standard notation e.g. "Am"
        let energy: Double?     // 0–10
        let danceability: Double? // 0–10
    }

    // MARK: - Full analysis via Claude

    /// Ask Claude for the complete track analysis — BPM, key, energy, danceability.
    /// Claude uses its training data + web search. Returns quickly for known tracks.
    static func analyseTrack(title: String, artist: String) async -> Metadata {
        guard let claudePath = findClaude() else {
            return await legacyLookup(title: title, artist: artist)
        }

        let prompt = """
        You are a DJ music expert. For the track "\(title)" by \(artist), provide accurate DJ metadata.
        Search the web to verify. Return ONLY a single JSON object with no explanation:
        {
          "bpm": <integer or null>,
          "camelot_key": "<Camelot notation e.g. 8A, 4B, or null>",
          "musical_key": "<standard key e.g. Am, F major, or null>",
          "energy": <0.0-10.0 float or null>,
          "danceability": <0.0-10.0 float or null>
        }
        """

        return await Task.detached(priority: .utility) {
            guard let output = shell(claudePath, args: [
                "--output-format", "text",
                "--dangerously-skip-permissions",
                "-p", prompt,
            ]) else { return Metadata(bpm: nil, key: nil, musicalKey: nil, energy: nil, danceability: nil) }
            return parseFullJSON(from: output)
        }.value
    }

    /// Legacy BPM-only lookup used by enqueueBPMLookup.
    static func lookup(title: String, artist: String) async -> (bpm: Int?, key: String?) {
        let meta = await analyseTrack(title: title, artist: artist)
        return (meta.bpm, meta.key)
    }

    // MARK: - JSON parsing

    private static func parseFullJSON(from text: String) -> Metadata {
        guard let start = text.firstIndex(of: "{"),
              let end   = text.lastIndex(of: "}"),
              let data  = String(text[start...end]).data(using: .utf8),
              let obj   = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return Metadata(bpm: nil, key: nil, musicalKey: nil, energy: nil, danceability: nil) }

        var bpm: Int?
        if let v = obj["bpm"] {
            if let n = v as? Int         { bpm = n }
            else if let d = v as? Double { bpm = Int(d) }
            else if let s = v as? String { bpm = Int(s) }
        }

        func str(_ k: String) -> String? {
            guard let s = obj[k] as? String, s != "null", !s.isEmpty else { return nil }
            return s
        }
        func dbl(_ k: String) -> Double? {
            if let d = obj[k] as? Double { return d }
            if let i = obj[k] as? Int    { return Double(i) }
            return nil
        }

        return Metadata(
            bpm:          bpm,
            key:          str("camelot_key"),
            musicalKey:   str("musical_key"),
            energy:       dbl("energy"),
            danceability: dbl("danceability")
        )
    }

    // MARK: - Legacy fallback (no Claude)

    private static func legacyLookup(title: String, artist: String) async -> Metadata {
        Metadata(bpm: nil, key: nil, musicalKey: nil, energy: nil, danceability: nil)
    }

    // MARK: - Helpers

    static func findClaude() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "/usr/bin/claude",
        ].first { FileManager.default.fileExists(atPath: $0) }
    }

    private static func shell(_ path: String, args: [String]) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        // Strip CLAUDECODE so nested claude sessions are allowed
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "CLAUDECODE")
        proc.environment = env
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError  = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let str  = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (str?.isEmpty == false) ? str : nil
    }
}

// MARK: - DJ Pool search URLs

enum DJPool {
    struct Source {
        let name: String
        let searchURL: (String, String) -> String
    }

    static let sources: [Source] = [
        Source(name: "Beatsource") { title, artist in
            let q = "\(artist) \(title)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            return "https://www.beatsource.com/search/tracks?q=\(q)"
        },
        Source(name: "Beatport") { title, artist in
            let q = "\(artist) \(title)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            return "https://www.beatport.com/search/tracks?q=\(q)"
        },
        Source(name: "Traxsource") { title, artist in
            let q = "\(artist) \(title)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            return "https://www.traxsource.com/search?term=\(q)"
        },
        Source(name: "SoundCloud") { title, artist in
            let q = "\(artist) \(title)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            return "https://soundcloud.com/search?q=\(q)"
        },
    ]

    /// Returns path to yt-dlp if installed (used for SoundCloud download)
    static var ytDlpPath: String? {
        ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp"]
            .first { FileManager.default.fileExists(atPath: $0) }
    }

    /// Downloads a track from SoundCloud using yt-dlp into ~/Music/Crates/.
    /// Completion is called on the main thread with the actual downloaded file path, or nil on failure.
    static func downloadFromSoundCloud(title: String, artist: String, completion: @escaping (String?) -> Void) {
        guard let ytdlp = ytDlpPath else { completion(nil); return }

        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Music/Crates")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let query       = "scsearch1:\(artist) \(title)"
        let outTemplate = dir.appendingPathComponent("%(artist)s - %(title)s.%(ext)s").path
        let beforeFiles = Set(audioFilesInDir(dir))
        let startTime   = Date()

        DispatchQueue.global(qos: .utility).async {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: ytdlp)
            proc.arguments = [
                query,
                "-x",
                "--audio-format", "mp3",
                "--audio-quality", "0",
                "-o", outTemplate,
                "--no-playlist",
            ]
            proc.standardOutput = Pipe()
            proc.standardError  = Pipe()
            try? proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            // Find the file that appeared in the directory since we started
            let afterFiles = Set(audioFilesInDir(dir))
            let newFiles   = afterFiles.subtracting(beforeFiles)
            // Also accept any file touched in the last 120s as fallback
            let filePath: String? = newFiles.first ?? audioFilesInDir(dir).filter { path in
                let url  = URL(fileURLWithPath: path)
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return date > startTime
            }.first
            DispatchQueue.main.async { completion(filePath) }
        }
    }

    private static func audioFilesInDir(_ dir: URL) -> [String] {
        let exts: Set<String> = ["mp3", "m4a", "aac", "ogg", "flac", "wav", "aiff"]
        return (try? FileManager.default.contentsOfDirectory(at: dir,
                                                             includingPropertiesForKeys: nil))?.compactMap { url in
            exts.contains(url.pathExtension.lowercased()) ? url.path : nil
        } ?? []
    }
}
