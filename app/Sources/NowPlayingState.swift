import Foundation

struct NowPlayingTrack: Equatable {
    let title: String
    let artist: String
    let isPlaying: Bool
}

class NowPlayingState: ObservableObject {
    @Published var currentTrack: NowPlayingTrack?

    /// Path to nowplaying-cli if installed, checked once at startup.
    static let cliPath: String? = {
        ["/opt/homebrew/bin/nowplaying-cli",
         "/usr/local/bin/nowplaying-cli",
         "/usr/bin/nowplaying-cli"]
            .first { FileManager.default.fileExists(atPath: $0) }
    }()

    var isCliAvailable: Bool { NowPlayingState.cliPath != nil }

    private var pollTask: Task<Void, Never>?

    init() { startPolling() }

    deinit { pollTask?.cancel() }

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                let track = NowPlayingState.fetchSync()
                await MainActor.run { self?.currentTrack = track }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    // MARK: - Fetch (blocking, runs off main thread)

    private static func fetchSync() -> NowPlayingTrack? {
        // Primary: nowplaying-cli
        if let path = cliPath, let track = fetchViaCLI(path: path) {
            return track
        }
        // Fallback: osascript → Spotify
        return fetchViaSpotifyScript()
    }

    private static func fetchViaCLI(path: String) -> NowPlayingTrack? {
        guard let title = run(path, ["get", "title"]),
              !title.isEmpty, title != "null" else { return nil }

        let artist    = run(path, ["get", "artist"]) ?? ""
        let rateStr   = run(path, ["get", "playbackRate"]) ?? "0"
        let isPlaying = (Double(rateStr) ?? 0) > 0

        return NowPlayingTrack(
            title: title,
            artist: artist == "null" ? "" : artist,
            isPlaying: isPlaying
        )
    }

    private static func fetchViaSpotifyScript() -> NowPlayingTrack? {
        let script = """
        try
            tell application "Spotify"
                if it is running and player state is playing then
                    return (name of current track) & "\n" & (artist of current track) & "\n1"
                end if
            end tell
        end try
        return "\n\n0"
        """
        guard let out = run("/usr/bin/osascript", ["-e", script]) else { return nil }
        let lines = out.components(separatedBy: "\n")
        guard lines.count >= 2, !lines[0].trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return NowPlayingTrack(
            title: lines[0],
            artist: lines[1],
            isPlaying: lines.count > 2 && lines[2].trimmingCharacters(in: .whitespaces) == "1"
        )
    }

    // MARK: - Shell helper

    private static func run(_ path: String, _ args: [String]) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
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
