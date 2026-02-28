import Foundation

// MARK: - Result type

struct TrackAnalysis {
    var bpm:              Int?
    var camelotKey:       String?    // e.g. "8A"
    var musicalKey:       String?    // e.g. "Am"
    var energy:           Double?    // 0–10
    var danceability:     Double?    // 0–10
    var loudnessDb:       Double?    // dBFS
    var tempoStability:   Double?    // 0–1
    var onsetRate:        Double?    // events/sec
    var spectralContrast: Double?
    var analyser:         String?    // "librosa" | "mutagen" | "none"
}

// MARK: - Analyser

enum TrackAnalyzer {

    // MARK: Paths

    /// Path to the bundled Python analysis script.
    static var scriptPath: String? {
        if let p = Bundle.main.path(forResource: "analyze_tracks", ofType: "py") { return p }
        let bin = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        let dev = bin.deletingLastPathComponent().appendingPathComponent("analyze_tracks.py").path
        return FileManager.default.fileExists(atPath: dev) ? dev : nil
    }

    /// First Python 3 interpreter found on the system.
    static var pythonPath: String? {
        for path in ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"] {
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        return nil
    }

    // MARK: - Folder analysis (NDJSON streaming)

    /// Runs the Python analysis script on all `urls` in **one subprocess**.
    /// Calls `onResult` on the main actor for each file as results stream in.
    static func analyzeFolder(
        urls: [URL],
        onResult: @MainActor @escaping (URL, TrackAnalysis?) -> Void
    ) async {
        guard !urls.isEmpty else { return }
        guard let python = pythonPath, let script = scriptPath else {
            for url in urls { await onResult(url, nil) }
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: python)
        proc.arguments     = [script] + urls.map(\.path)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError  = stderrPipe

        do {
            try proc.run()
            NSLog("[TrackAnalyzer] python process launched pid=\(proc.processIdentifier)")
        } catch {
            NSLog("[TrackAnalyzer] failed to launch python: \(error)")
            for url in urls { await onResult(url, nil) }
            return
        }

        // Stream NDJSON line by line as Python writes results.
        // `bytes.lines` requires macOS 12+ — we target 13 so this is fine.
        let handle = stdoutPipe.fileHandleForReading
        do {
            for try await line in handle.bytes.lines {
                guard let data   = String(line).data(using: .utf8),
                      let obj    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let pathStr = obj["path"] as? String
                else { continue }

                let url = URL(fileURLWithPath: pathStr)

                if let err = obj["error"] as? String, !err.isEmpty {
                    await onResult(url, nil)
                    continue
                }

                var a = TrackAnalysis()
                if let bpm = obj["bpm"] as? Double, bpm > 0 { a.bpm = Int(bpm.rounded()) }
                a.camelotKey       = obj["camelot_key"]       as? String
                a.musicalKey       = obj["musical_key"]       as? String
                a.energy           = obj["energy"]            as? Double
                a.danceability     = obj["danceability"]      as? Double
                a.loudnessDb       = obj["loudness_db"]       as? Double
                a.tempoStability   = obj["tempo_stability"]   as? Double
                a.onsetRate        = obj["onset_rate"]        as? Double
                a.spectralContrast = obj["spectral_contrast"] as? Double
                a.analyser         = obj["analyser"]          as? String

                await onResult(url, a)
            }
        } catch {
            NSLog("[TrackAnalyzer] pipe read error: \(error)")
        }

        proc.waitUntilExit()
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if !stderr.isEmpty {
            NSLog("[TrackAnalyzer] python stderr:\n\(stderr)")
        }
        NSLog("[TrackAnalyzer] python exited with status \(proc.terminationStatus)")
    }
}
