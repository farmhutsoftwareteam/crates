import Foundation
import Combine

enum SongSource: String, Codable {
    case spotify    // added via Spotify integration — no local file
    case manual     // added by hand — no local file
    case localFile  // imported from a local folder on disk
    case downloaded // downloaded via yt-dlp (SoundCloud etc.)

    /// Backwards-compat: old saves stored "manual" for both folder imports
    /// and hand-adds. If a song has localFilePath set but source == .manual,
    /// treat it as .localFile.
    func resolved(hasLocalFile: Bool) -> SongSource {
        if self == .manual && hasLocalFile { return .localFile }
        return self
    }
}

struct Song: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var artist: String
    var bpm: Int?
    var key: String?            // Camelot (e.g. "8A") or standard (e.g. "Am")
    var musicalKey: String?     // Standard key name from librosa (e.g. "Am")
    var durationMs: Int?
    var notes: String
    var spotifyId: String?
    var albumArtURL: String?
    var addedAt: Date
    var source: SongSource
    // ── Deep analysis fields (populated by TrackAnalyzer / librosa) ──────────
    var energy:           Double?   // 0–10 energy score
    var danceability:     Double?   // 0–10 danceability
    var loudnessDb:       Double?   // dBFS loudness
    var tempoStability:   Double?   // 0–1 (1 = perfectly stable)
    var localFilePath:    String?   // absolute path to local audio file

    init(
        id: UUID = UUID(),
        title: String,
        artist: String,
        bpm: Int? = nil,
        key: String? = nil,
        musicalKey: String? = nil,
        durationMs: Int? = nil,
        notes: String = "",
        spotifyId: String? = nil,
        albumArtURL: String? = nil,
        addedAt: Date = Date(),
        source: SongSource = .manual,
        energy: Double? = nil,
        danceability: Double? = nil,
        loudnessDb: Double? = nil,
        tempoStability: Double? = nil,
        localFilePath: String? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.bpm = bpm
        self.key = key
        self.musicalKey = musicalKey
        self.durationMs = durationMs
        self.notes = notes
        self.spotifyId = spotifyId
        self.albumArtURL = albumArtURL
        self.addedAt = addedAt
        self.source = source
        self.energy = energy
        self.danceability = danceability
        self.loudnessDb = loudnessDb
        self.tempoStability = tempoStability
        self.localFilePath = localFilePath
    }
}

struct Crate: Codable, Identifiable {
    let id: UUID
    var name: String
    var emoji: String
    var songs: [Song]
    var createdAt: Date
    var folderPath: String?   // original import folder — used to re-discover files for re-analysis

    init(
        id: UUID = UUID(),
        name: String,
        emoji: String = "🎵",
        songs: [Song] = [],
        createdAt: Date = Date(),
        folderPath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.songs = songs
        self.createdAt = createdAt
        self.folderPath = folderPath
    }
}

struct AnalysisResult: Equatable {
    let crateId: UUID
    let total:   Int
    let failed:  Int
}

class CrateState: ObservableObject {
    @Published var crates: [Crate] = []
    @Published var activeCrateId: UUID?
    /// Song IDs currently undergoing Claude BPM/key lookup
    @Published var pendingLookups: Set<UUID> = []
    /// Crate IDs currently being built from a folder import (shows progress bar)
    @Published var importingCrateIds: Set<UUID> = []
    /// Crate IDs currently undergoing deep audio analysis (shows progress bar)
    @Published var analysingCrateIds: Set<UUID> = []
    /// Song IDs currently undergoing librosa deep analysis (shows pulsing dot)
    @Published var pendingAnalysis: Set<UUID> = []
    /// Song IDs whose analysis failed (shows ⚠ in energy column)
    @Published var analysisFailedIds: Set<UUID> = []
    /// Result of the most recent crate analysis — shown as a brief banner
    @Published var lastAnalysisResult: AnalysisResult? = nil
    /// Cached Set Intel results keyed by crate ID — persisted across sessions
    @Published var setIntelCache: [UUID: SetIntel] = [:]

    private let persistenceURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Crates", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("crates.json")
    }()

    private let intelURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Crates", isDirectory: true)
        return dir.appendingPathComponent("intel.json")
    }()

    private var saveCancellable: AnyCancellable?

    init() {
        load()
        loadIntel()
        // Auto-select first crate if none selected
        if activeCrateId == nil {
            activeCrateId = crates.first?.id
        }
        // Debounced auto-save on every change
        saveCancellable = objectWillChange
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.save() }
    }

    var activeCrate: Crate? {
        guard let id = activeCrateId else { return nil }
        return crates.first { $0.id == id }
    }

    // MARK: - Crate operations

    func addCrate(name: String, emoji: String = "🎵") {
        let crate = Crate(name: name, emoji: emoji)
        crates.append(crate)
        activeCrateId = crate.id
    }

    func deleteCrate(_ crate: Crate) {
        crates.removeAll { $0.id == crate.id }
        setIntelCache.removeValue(forKey: crate.id)
        if activeCrateId == crate.id {
            activeCrateId = crates.first?.id
        }
    }

    func renameCrate(_ id: UUID, name: String) {
        guard let idx = crates.firstIndex(where: { $0.id == id }) else { return }
        crates[idx].name = name
    }

    // MARK: - Song operations

    func addSong(_ song: Song, to crateId: UUID? = nil) {
        let targetId = crateId ?? activeCrateId
        guard let targetId, let idx = crates.firstIndex(where: { $0.id == targetId }) else { return }
        // Avoid duplicate Spotify tracks
        if let spotifyId = song.spotifyId,
           crates[idx].songs.contains(where: { $0.spotifyId == spotifyId }) {
            return
        }
        crates[idx].songs.append(song)
    }

    func removeSong(_ song: Song, from crateId: UUID) {
        guard let idx = crates.firstIndex(where: { $0.id == crateId }) else { return }
        crates[idx].songs.removeAll { $0.id == song.id }
    }

    func moveSongs(in crateId: UUID, from source: IndexSet, to destination: Int) {
        guard let idx = crates.firstIndex(where: { $0.id == crateId }) else { return }
        var songs = crates[idx].songs
        // Manual move: collect items, remove them, insert at destination
        let items = source.sorted().map { songs[$0] }
        for idx in source.sorted().reversed() { songs.remove(at: idx) }
        var adjustedDest = destination
        for offset in source.reversed() {
            if offset < destination { adjustedDest -= 1 }
        }
        songs.insert(contentsOf: items, at: adjustedDest)
        crates[idx].songs = songs
    }

    func updateSong(_ song: Song, in crateId: UUID) {
        guard let crateIdx = crates.firstIndex(where: { $0.id == crateId }),
              let songIdx = crates[crateIdx].songs.firstIndex(where: { $0.id == song.id }) else { return }
        crates[crateIdx].songs[songIdx] = song
    }

    func reorderSongs(in crateId: UUID, titles: [String]) {
        guard let crateIdx = crates.firstIndex(where: { $0.id == crateId }) else { return }
        let existing = crates[crateIdx].songs
        var reordered: [Song] = []
        for title in titles {
            if let song = existing.first(where: { $0.title.lowercased() == title.lowercased() }) {
                reordered.append(song)
            }
        }
        // Append any songs not matched by title
        let matched = Set(reordered.map { $0.id })
        let remainder = existing.filter { !matched.contains($0.id) }
        crates[crateIdx].songs = reordered + remainder
    }

    // MARK: - Folder import

    /// Imports all audio files from `url` as a new crate.
    ///
    /// **Two-pass pipeline:**
    /// 1. Fast pass — AVFoundation reads existing ID3 tags; songs appear immediately.
    /// 2. Deep pass — librosa analyses audio for accurate BPM, key, energy, danceability.
    ///    Updates each song in-place as results stream back. Falls back to Claude lookup
    ///    if librosa is unavailable and a track has no tagged BPM.
    func importFolder(url: URL) {
        let name  = url.lastPathComponent
        let crate = Crate(name: name, emoji: emojiFor(name: name), folderPath: url.path)
        crates.append(crate)
        activeCrateId = crate.id
        importingCrateIds.insert(crate.id)

        Task {
            let fileURLs = scanAudioFiles(in: url)
            guard !fileURLs.isEmpty else {
                await MainActor.run { self.importingCrateIds.remove(crate.id) }
                return
            }

            // ── Pass 1: AVFoundation fast metadata (existing ID3 tags) ──────────
            var results: [(Int, Song)] = []
            await withTaskGroup(of: (Int, Song).self) { group in
                for (idx, fileURL) in fileURLs.enumerated() {
                    group.addTask {
                        let meta = await AudioFileImporter.read(url: fileURL)
                        return (idx, Song(
                            title:         meta.title,
                            artist:        meta.artist,
                            bpm:           meta.bpm,
                            key:           meta.key,
                            durationMs:    meta.durationMs,
                            source:        .localFile,
                            localFilePath: fileURL.path
                        ))
                    }
                }
                for await pair in group { results.append(pair) }
            }

            results.sort { $0.0 < $1.0 }
            let songs = results.map(\.1)

            // Make songs visible right away
            await MainActor.run {
                if let idx = self.crates.firstIndex(where: { $0.id == crate.id }) {
                    self.crates[idx].songs = songs
                }
                self.importingCrateIds.remove(crate.id)
            }

            // ── Pass 2: Auto deep-analysis scan ─────────────────────────────────
            // Always attempt Python analysis; the script falls back to mutagen if
            // librosa is absent. If Python itself isn't found, analyzeFolder fires
            // nil results for every file and we fall back to Claude BPM lookup.

            // Mark all songs as pending analysis
            await MainActor.run {
                for song in songs { self.pendingAnalysis.insert(song.id) }
            }

            // URL → song ID map for matching streamed results back to songs
            let urlToId: [String: UUID] = Dictionary(
                uniqueKeysWithValues: songs.compactMap { s in
                    s.localFilePath.map { ($0, s.id) }
                }
            )

            var analysisHit = false   // did we get at least one useful result?

            await TrackAnalyzer.analyzeFolder(urls: fileURLs) { [weak self] resultURL, analysis in
                guard let self else { return }
                if let songId = urlToId[resultURL.path] {
                    self.applyAnalysis(analysis, to: songId)
                    self.pendingAnalysis.remove(songId)
                    if analysis?.bpm != nil || analysis?.energy != nil { analysisHit = true }
                }
            }

            // Clear any remaining pending markers (errored files, mismatched paths)
            await MainActor.run {
                for song in songs { self.pendingAnalysis.remove(song.id) }
            }

            // If analysis yielded nothing (no Python / no librosa) fall back to Claude BPM
            if !analysisHit {
                await MainActor.run {
                    for song in songs where song.bpm == nil {
                        self.enqueueBPMLookup(for: song)
                    }
                }
            }
        }
    }

    /// Applies a `TrackAnalysis` result to the song with the given ID across all crates.
    /// Called on the main actor (via TrackAnalyzer.analyzeFolder callback).
    @MainActor
    private func applyAnalysis(_ analysis: TrackAnalysis?, to songId: UUID) {
        guard let analysis else { return }
        for ci in crates.indices {
            guard let si = crates[ci].songs.firstIndex(where: { $0.id == songId }) else { continue }
            // BPM: prefer librosa if we didn't already have a tagged value
            if let bpm = analysis.bpm { crates[ci].songs[si].bpm = bpm }
            // Key: use Camelot from librosa (more consistent display)
            if let key = analysis.camelotKey, !key.isEmpty, key != "—" {
                crates[ci].songs[si].key = key
            }
            if let mk = analysis.musicalKey { crates[ci].songs[si].musicalKey = mk }
            // Energy & vibe fields
            crates[ci].songs[si].energy         = analysis.energy
            crates[ci].songs[si].danceability   = analysis.danceability
            crates[ci].songs[si].loudnessDb      = analysis.loudnessDb
            crates[ci].songs[si].tempoStability  = analysis.tempoStability
            break
        }
    }

    private func scanAudioFiles(in url: URL) -> [URL] {
        let exts = FolderWatcher.audioExtensions
        let fm   = FileManager.default
        let opts: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
        guard let enumerator = fm.enumerator(at: url,
                                              includingPropertiesForKeys: [.isRegularFileKey],
                                              options: opts) else { return [] }
        var urls: [URL] = []
        for case let fileURL as URL in enumerator {
            if exts.contains(fileURL.pathExtension.lowercased()) {
                urls.append(fileURL)
            }
        }
        // Sort by filename — DJs often number files: "01 - Track.mp3"
        return urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func emojiFor(name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("open") || lower.contains("warm")  { return "🌅" }
        if lower.contains("peak") || lower.contains("main")  { return "🔥" }
        if lower.contains("close") || lower.contains("end")  { return "🌙" }
        if lower.contains("afro") || lower.contains("amapiano") { return "🌍" }
        if lower.contains("house")                           { return "🏠" }
        if lower.contains("techno")                          { return "⚡" }
        return "📁"
    }

    // MARK: - Re-analyse

    /// Re-analyses every song in a crate using Claude (title + artist → BPM, key, energy, danceability).
    /// No file paths needed — Claude knows most tracks from training + web search.
    func reanalyseCrate(id: UUID, overrideFolderURL: URL? = nil) {
        guard let crateIdx = crates.firstIndex(where: { $0.id == id }) else { return }
        guard !analysingCrateIds.contains(id) else { return }

        let songs = crates[crateIdx].songs
        guard !songs.isEmpty else { return }

        // Persist folder path if provided
        if let p = overrideFolderURL?.path { crates[crateIdx].folderPath = p }

        analysingCrateIds.insert(id)
        for song in songs {
            pendingAnalysis.insert(song.id)
            analysisFailedIds.remove(song.id)
        }

        Task {
            // Run up to 4 Claude queries concurrently
            await withTaskGroup(of: (UUID, BPMService.Metadata).self) { group in
                var inFlight = 0
                var iterator = songs.makeIterator()

                // Seed initial batch
                while inFlight < 4, let song = iterator.next() {
                    let s = song
                    group.addTask { await (s.id, BPMService.analyseTrack(title: s.title, artist: s.artist)) }
                    inFlight += 1
                }

                // As each finishes, update the song and launch the next
                for await (songId, meta) in group {
                    await MainActor.run {
                        guard let ci = self.crates.firstIndex(where: { $0.id == id }),
                              let si = self.crates[ci].songs.firstIndex(where: { $0.id == songId })
                        else { return }

                        if meta.bpm != nil || meta.key != nil || meta.energy != nil {
                            if let bpm = meta.bpm { self.crates[ci].songs[si].bpm = bpm }
                            if let key = meta.key { self.crates[ci].songs[si].key = key }
                            if let mk  = meta.musicalKey { self.crates[ci].songs[si].musicalKey = mk }
                            if let e   = meta.energy     { self.crates[ci].songs[si].energy = e }
                            if let d   = meta.danceability { self.crates[ci].songs[si].danceability = d }
                            self.analysisFailedIds.remove(songId)
                        } else {
                            self.analysisFailedIds.insert(songId)
                        }
                        self.pendingAnalysis.remove(songId)
                    }

                    // Refill the batch
                    if let next = iterator.next() {
                        let s = next
                        group.addTask { await (s.id, BPMService.analyseTrack(title: s.title, artist: s.artist)) }
                    }
                }
            }

            await MainActor.run {
                for song in songs { self.pendingAnalysis.remove(song.id) }
                self.analysingCrateIds.remove(id)
                let failed = songs.filter { self.analysisFailedIds.contains($0.id) }.count
                self.lastAnalysisResult = AnalysisResult(crateId: id, total: songs.count, failed: failed)
            }
        }
    }

    /// Re-runs the full librosa analysis on a single song (must have a localFilePath).
    /// Falls back to Claude BPM lookup if no local file is known.
    func reanalyse(song: Song) {
        guard !pendingAnalysis.contains(song.id) else { return }
        pendingAnalysis.insert(song.id)
        analysisFailedIds.remove(song.id)

        Task {
            let meta = await BPMService.analyseTrack(title: song.title, artist: song.artist)
            await MainActor.run {
                for ci in self.crates.indices {
                    guard let si = self.crates[ci].songs.firstIndex(where: { $0.id == song.id }) else { continue }
                    if meta.bpm != nil || meta.key != nil || meta.energy != nil {
                        if let bpm = meta.bpm { self.crates[ci].songs[si].bpm = bpm }
                        if let key = meta.key { self.crates[ci].songs[si].key = key }
                        if let mk  = meta.musicalKey { self.crates[ci].songs[si].musicalKey = mk }
                        if let e   = meta.energy     { self.crates[ci].songs[si].energy = e }
                        if let d   = meta.danceability { self.crates[ci].songs[si].danceability = d }
                    } else {
                        self.analysisFailedIds.insert(song.id)
                    }
                    break
                }
                self.pendingAnalysis.remove(song.id)
            }
        }
    }

    // MARK: - BPM / Key lookup

    /// Fires a background BPM+key lookup for a song that has neither.
    func enqueueBPMLookup(for song: Song) {
        guard song.bpm == nil, song.key == nil,
              !pendingLookups.contains(song.id) else { return }
        pendingLookups.insert(song.id)

        Task {
            let meta = await BPMService.lookup(title: song.title, artist: song.artist)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.pendingLookups.remove(song.id)
                guard meta.bpm != nil || meta.key != nil else { return }
                // Find the song across all crates and update it
                for ci in self.crates.indices {
                    if let si = self.crates[ci].songs.firstIndex(where: { $0.id == song.id }) {
                        if let bpm = meta.bpm { self.crates[ci].songs[si].bpm = bpm }
                        if let key = meta.key { self.crates[ci].songs[si].key = key }
                        break
                    }
                }
            }
        }
    }

    // MARK: - Persistence

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(crates) else { return }
        try? data.write(to: persistenceURL, options: .atomic)
    }

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: persistenceURL),
              let loaded = try? decoder.decode([Crate].self, from: data) else {
            // Seed with a default crate on first launch
            crates = [Crate(name: "My First Set", emoji: "🎵")]
            return
        }
        crates = loaded
    }

    // MARK: - Set Intel cache persistence

    func cacheSetIntel(_ intel: SetIntel, for crateId: UUID) {
        setIntelCache[crateId] = intel
        saveIntel()
    }

    private func saveIntel() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let stringKeyed = Dictionary(uniqueKeysWithValues: setIntelCache.map { ($0.key.uuidString, $0.value) })
        guard let data = try? encoder.encode(stringKeyed) else { return }
        try? data.write(to: intelURL, options: .atomic)
    }

    private func loadIntel() {
        let decoder = JSONDecoder()
        guard let data = try? Data(contentsOf: intelURL),
              let loaded = try? decoder.decode([String: SetIntel].self, from: data) else { return }
        setIntelCache = Dictionary(uniqueKeysWithValues: loaded.compactMap { k, v in
            UUID(uuidString: k).map { ($0, v) }
        })
    }
}
