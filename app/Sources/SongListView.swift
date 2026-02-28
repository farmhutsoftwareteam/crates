import SwiftUI

struct SongListView: View {
    let crate: Crate
    @EnvironmentObject var crateState: CrateState

    @State private var analysisToast: String? = nil
    @State private var toastTask: Task<Void, Never>? = nil

    var isAnalysing: Bool { crateState.analysingCrateIds.contains(crate.id) }

    var body: some View {
        VStack(spacing: 0) {
            // ── Crate header ─────────────────────────────────────
            HStack(spacing: 10) {
                Text(crate.emoji)
                    .font(.system(size: 18))
                Text(crate.name.uppercased())
                    .font(.system(size: 12, weight: .black))
                    .tracking(2)
                    .foregroundColor(.cratesPrimary)
                Spacer()
                if isAnalysing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini).tint(.cratesAccent)
                        Text("ANALYSING…")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(1.5)
                            .foregroundColor(.cratesAccent)
                    }
                } else if let toast = analysisToast {
                    Text(toast)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundColor(toast.contains("failed") ? .red.opacity(0.8) : .cratesLive)
                        .transition(.opacity)
                } else {
                    Text("\(crate.songs.count) TRACKS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundColor(.cratesDim)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: isAnalysing)
            .animation(.easeInOut(duration: 0.3), value: analysisToast)
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            .onChange(of: crateState.lastAnalysisResult) { result in
                guard let result, result.crateId == crate.id else { return }
                let msg = result.failed == 0
                    ? "ANALYSIS DONE · \(result.total) TRACKS"
                    : "DONE · \(result.total - result.failed) OK · \(result.failed) FAILED"
                withAnimation { analysisToast = msg }
                toastTask?.cancel()
                toastTask = Task {
                    try? await Task.sleep(for: .seconds(4))
                    if !Task.isCancelled {
                        withAnimation { analysisToast = nil }
                    }
                }
            }

            // ── Column headers ───────────────────────────────────
            HStack(spacing: 0) {
                Text("#")
                    .frame(width: 44, alignment: .trailing)
                Color.clear.frame(width: 46)   // art
                Text("TITLE")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 10)
                Text("BPM")
                    .frame(width: 54, alignment: .center)
                Text("KEY")
                    .frame(width: 48, alignment: .center)
                Text("NRG")
                    .frame(width: 34, alignment: .center)
                Text("NOTES")
                    .frame(width: 148, alignment: .leading)
                    .padding(.leading, 4)
                Spacer().frame(width: 16)
            }
            .font(.system(size: 9, weight: .black))
            .tracking(2)
            .foregroundColor(.cratesGhost)
            .padding(.horizontal, 16)
            .padding(.bottom, 6)

            Rectangle()
                .fill(Color.cratesBorder)
                .frame(height: 1)

            // ── Songs ────────────────────────────────────────────
            if crate.songs.isEmpty {
                EmptyCrateView()
            } else {
                List {
                    ForEach(Array(crate.songs.enumerated()), id: \.element.id) { index, song in
                        SongCard(song: song, position: index + 1, crateId: crate.id)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets())
                            .contextMenu {
                                Button("Re-analyse") { crateState.reanalyse(song: song) }
                                Divider()
                                ForEach(DJPool.sources, id: \.name) { source in
                                    Button("Find on \(source.name)") {
                                        if let url = URL(string: source.searchURL(song.title, song.artist)) {
                                            NSWorkspace.shared.open(url)
                                        }
                                    }
                                }
                                if DJPool.ytDlpPath != nil {
                                    Divider()
                                    Button("Download from SoundCloud") {
                                        DJPool.downloadFromSoundCloud(title: song.title, artist: song.artist) { _ in }
                                    }
                                }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    crateState.removeSong(song, from: crate.id)
                                }
                            }
                    }
                    .onMove { crateState.moveSongs(in: crate.id, from: $0, to: $1) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.cratesBg)
            }
        }
        .background(Color.cratesBg)
    }
}

struct EmptyCrateView: View {
    var body: some View {
        VStack(spacing: 16) {
            // Decorative "waveform" placeholder
            HStack(alignment: .center, spacing: 3) {
                ForEach([6, 14, 10, 20, 8, 24, 12, 18, 6, 22, 10, 16, 8].indices, id: \.self) { i in
                    let heights: [CGFloat] = [6, 14, 10, 20, 8, 24, 12, 18, 6, 22, 10, 16, 8]
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.cratesGhost)
                        .frame(width: 4, height: heights[i])
                }
            }
            Text("NO TRACKS YET")
                .font(.system(size: 9, weight: .black))
                .tracking(3)
                .foregroundColor(.cratesGhost)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cratesBg)
    }
}
