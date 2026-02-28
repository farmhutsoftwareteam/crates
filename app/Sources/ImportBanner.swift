import SwiftUI

/// Slide-in notification shown when a new audio file is detected in the watched folder.
/// Reads metadata from the file and offers to add it to the active crate.
struct ImportBanner: View {
    let url: URL
    @EnvironmentObject var crateState:    CrateState
    @EnvironmentObject var folderWatcher: FolderWatcher

    @State private var meta:    AudioFileMeta?
    @State private var loading  = true
    @State private var added    = false

    private var filename: String { url.deletingPathExtension().lastPathComponent }

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.cratesAccent.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: added ? "checkmark" : "arrow.down")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(added ? .cratesLive : .cratesAccent)
            }

            // Info
            VStack(alignment: .leading, spacing: 3) {
                if loading {
                    Text(filename)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.cratesPrimary)
                        .lineLimit(1)
                    Text("Reading tags…")
                        .font(.system(size: 10))
                        .foregroundColor(.cratesDim)
                } else if let m = meta {
                    Text(m.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.cratesPrimary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(m.artist.isEmpty ? "Unknown artist" : m.artist)
                            .font(.system(size: 10))
                            .foregroundColor(.cratesDim)
                        if let bpm = m.bpm {
                            Text("·")
                                .foregroundColor(.cratesGhost)
                            Text("\(bpm) BPM")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.cratesAccent)
                        }
                        if let key = m.key {
                            Text("·")
                                .foregroundColor(.cratesGhost)
                            Text(key)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.cratesKey)
                        }
                    }
                }
            }

            Spacer(minLength: 8)

            if !added {
                // Add button
                Button(added ? "Added" : "+ Crate") {
                    importTrack()
                }
                .buttonStyle(AccentButtonStyle())
                .disabled(loading || crateState.activeCrateId == nil)
            }

            // Dismiss
            Button {
                folderWatcher.dismiss(url)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.cratesDim)
                    .frame(width: 18, height: 18)
                    .background(Color.cratesBorder)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.cratesElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.cratesBorder, lineWidth: 1)
                )
        )
        .frame(maxWidth: 380)
        .task { await loadMeta() }
        // Auto-dismiss after adding
        .onChange(of: added) { if $0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                folderWatcher.dismiss(url)
            }
        }}
    }

    private func loadMeta() async {
        let m = await AudioFileImporter.read(url: url)
        await MainActor.run {
            meta    = m
            loading = false
        }
    }

    private func importTrack() {
        guard let m = meta else { return }
        let song = Song(
            title:      m.title,
            artist:     m.artist,
            bpm:        m.bpm,
            key:        m.key,
            durationMs: m.durationMs,
            notes:      "",
            source:     .manual
        )
        crateState.addSong(song)
        // If no BPM in tags, try Claude lookup
        if m.bpm == nil { crateState.enqueueBPMLookup(for: song) }
        added = true
    }
}
