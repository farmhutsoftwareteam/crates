import Foundation
import Combine

/// Watches a folder for new audio files using a kernel-level DispatchSource.
/// Publishes newly-detected files as `pendingImports` for the UI to handle.
class FolderWatcher: ObservableObject {
    @Published var pendingImports: [URL] = []

    static let audioExtensions: Set<String> = ["mp3", "m4a", "aiff", "aif", "wav", "flac", "ogg", "aac"]

    private(set) var watchedURL: URL
    private var source: DispatchSourceFileSystemObject?
    private var knownFiles: Set<String> = []

    init(url: URL? = nil) {
        watchedURL = url ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads")
        start()
    }

    func changeFolder(to url: URL) {
        source?.cancel()
        source = nil
        watchedURL = url
        start()
    }

    // MARK: - Watch lifecycle

    private func start() {
        // Snapshot existing files so we don't re-surface them on relaunch
        knownFiles = Set(audioFiles().map(\.lastPathComponent))

        let fd = open(watchedURL.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,          // fires when directory contents change
            queue: .global(qos: .utility)
        )

        src.setEventHandler { [weak self] in
            // Short delay so the file has time to finish writing before we stat it
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                self?.checkForNew()
            }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    private func checkForNew() {
        let current = audioFiles()
        let newURLs  = current.filter { !knownFiles.contains($0.lastPathComponent) }
        knownFiles   = Set(current.map(\.lastPathComponent))

        for url in newURLs where !pendingImports.contains(url) {
            pendingImports.insert(url, at: 0)   // newest first
        }
    }

    private func audioFiles() -> [URL] {
        let contents = try? FileManager.default.contentsOfDirectory(
            at: watchedURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: .skipsHiddenFiles
        )
        return (contents ?? []).filter {
            Self.audioExtensions.contains($0.pathExtension.lowercased())
        }
    }

    // MARK: - Dismiss

    func dismiss(_ url: URL) {
        pendingImports.removeAll { $0 == url }
    }

    deinit { source?.cancel() }
}
