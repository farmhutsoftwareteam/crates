import Foundation
import AVFoundation
import Combine

// MARK: - Shared audio engine

class AudioPlayer: ObservableObject {

    // State the UI observes
    @Published var currentSong: Song?  = nil
    @Published var isPlaying:   Bool   = false
    @Published var currentTime: Double = 0      // seconds
    @Published var duration:    Double = 0      // seconds
    @Published var volume:      Float  = 0.85

    // Queue
    private(set) var queue:        [Song] = []
    private(set) var currentIndex: Int    = -1

    var hasNext:     Bool { currentIndex < queue.count - 1 }
    var hasPrevious: Bool { currentIndex > 0 || currentTime > 3 }
    var queueCount:  Int  { queue.count }
    var queuePos:    Int  { currentIndex + 1 }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(currentTime / duration, 1)
    }

    // Internals
    private var player:       AVPlayer? = nil
    private var timeObserver: Any?      = nil
    private var cancellables            = Set<AnyCancellable>()

    // MARK: - Public API

    /// Load `song` and begin playback. `songs` becomes the navigation queue.
    func play(song: Song, in songs: [Song]) {
        guard let path = song.localFilePath else { return }
        let playable   = songs.filter { $0.localFilePath != nil }
        queue          = playable
        currentIndex   = playable.firstIndex(where: { $0.id == song.id }) ?? 0
        load(url: URL(fileURLWithPath: path), song: song)
    }

    func togglePlayPause() { isPlaying ? pause() : resume() }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func resume() {
        guard currentSong != nil else { return }
        player?.play()
        isPlaying = true
    }

    func next() {
        guard hasNext else { return }
        currentIndex += 1
        playCurrent()
    }

    func previous() {
        if currentTime > 3 {
            seek(to: 0)
        } else if currentIndex > 0 {
            currentIndex -= 1
            playCurrent()
        }
    }

    /// Seek to a fraction 0–1 of the track.
    func seek(to fraction: Double) {
        guard duration > 0 else { return }
        let secs = max(0, min(fraction, 1)) * duration
        let t    = CMTime(seconds: secs, preferredTimescale: 600)
        player?.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = secs
    }

    func setVolume(_ v: Float) {
        volume = max(0, min(v, 1))
        player?.volume = volume
    }

    // MARK: - Internal

    private func playCurrent() {
        let song = queue[currentIndex]
        guard let path = song.localFilePath else { next(); return }
        load(url: URL(fileURLWithPath: path), song: song)
    }

    private func load(url: URL, song: Song) {
        tearDown()

        let item = AVPlayerItem(url: url)

        if player == nil {
            player = AVPlayer(playerItem: item)
        } else {
            player?.replaceCurrentItem(with: item)
        }
        player?.volume = volume

        currentSong = song
        duration    = 0
        currentTime = 0

        // Duration — becomes known once status == .readyToPlay
        item.publisher(for: \.status)
            .filter { $0 == .readyToPlay }
            .first()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                let d = item.duration.seconds
                if d.isFinite, d > 0 { self?.duration = d }
            }
            .store(in: &cancellables)

        // Async fallback for duration (modern API)
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let d = try? await item.asset.load(.duration) {
                let secs = d.seconds
                if secs.isFinite, secs > 0, self.duration == 0 { self.duration = secs }
            }
        }

        // Periodic time updates (100 ms)
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: interval, queue: .main
        ) { [weak self] time in
            let s = time.seconds
            if s.isFinite, s >= 0 { self?.currentTime = s }
        }

        // End of track → auto-advance
        NotificationCenter.default
            .publisher(for: AVPlayerItem.didPlayToEndTimeNotification, object: item)
            .receive(on: DispatchQueue.main)
            .first()
            .sink { [weak self] _ in self?.trackDidEnd() }
            .store(in: &cancellables)

        player?.play()
        isPlaying = true
    }

    private func trackDidEnd() {
        if hasNext { next() } else { isPlaying = false; currentTime = 0 }
    }

    private func tearDown() {
        if let obs = timeObserver { player?.removeTimeObserver(obs); timeObserver = nil }
        cancellables.removeAll()
    }
}

// MARK: - Time formatting helper (shared with PlayerBar)

func audioTimeString(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let s = Int(seconds)
    return String(format: "%d:%02d", s / 60, s % 60)
}
