import SwiftUI

struct SongListView: View {
    let crate:       Crate
    var onOpenIntel: (() -> Void)? = nil

    @EnvironmentObject var crateState: CrateState

    @State private var analysisToast: String?          = nil
    @State private var toastTask:     Task<Void, Never>? = nil
    @State private var isEditingName  = false
    @State private var nameText       = ""
    @FocusState private var nameFocused: Bool

    var isAnalysing: Bool { crateState.analysingCrateIds.contains(crate.id) }

    private var bpmRange: String? {
        let bpms = crate.songs.compactMap { $0.bpm }.filter { $0 > 0 }
        guard !bpms.isEmpty else { return nil }
        let lo = bpms.min()!, hi = bpms.max()!
        return lo == hi ? "\(lo)" : "\(lo)–\(hi)"
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── Crate header ─────────────────────────────────────
            crateHeader

            // ── Column labels ────────────────────────────────────
            columnLabels

            Rectangle()
                .fill(Color.cratesBorder)
                .frame(height: 1)

            // ── Song list ─────────────────────────────────────────
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
                // ▼ removes the ~8px black gap macOS List adds at top
                .padding(.top, -8)
            }
        }
        .background(Color.cratesBg)
        .onChange(of: isEditingName) { editing in if editing { nameFocused = true } }
        .onChange(of: crateState.lastAnalysisResult) { result in
            guard let result, result.crateId == crate.id else { return }
            let msg = result.failed == 0
                ? "\(result.total) TRACKS · DONE"
                : "\(result.total - result.failed) OK  \(result.failed) FAILED"
            withAnimation { analysisToast = msg }
            toastTask?.cancel()
            toastTask = Task {
                try? await Task.sleep(for: .seconds(4))
                if !Task.isCancelled { withAnimation { analysisToast = nil } }
            }
        }
    }

    // MARK: - Crate header

    private var crateHeader: some View {
        HStack(spacing: 0) {
            // Orange left rail — visual anchor
            Rectangle()
                .fill(Color.cratesAccent)
                .frame(width: 3)

            HStack(spacing: 0) {
                // Emoji
                Text(crate.emoji)
                    .font(.system(size: 13))
                    .padding(.leading, 10)

                // Crate name — double-click to rename
                Group {
                    if isEditingName {
                        TextField("", text: $nameText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundColor(.cratesAccent)
                            .focused($nameFocused)
                            .onSubmit     { commitName() }
                            .onExitCommand { isEditingName = false }
                    } else {
                        Text(crate.name.uppercased())
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(.cratesPrimary)
                            .help("Double-click to rename")
                            .onTapGesture(count: 2) {
                                nameText     = crate.name
                                isEditingName = true
                            }
                    }
                }
                .padding(.leading, 8)

                Spacer()

                // Status area
                statusArea
                    .padding(.trailing, 8)

                // ANALYSE button
                if !crate.songs.isEmpty {
                    AnalyseButton(isRunning: isAnalysing) {
                        crateState.reanalyseCrate(id: crate.id)
                    }
                    .disabled(isAnalysing)
                }

                // SET INTEL button
                if !crate.songs.isEmpty, let onOpenIntel {
                    IntelButton(action: onOpenIntel)
                        .padding(.leading, 5)
                }

                Spacer().frame(width: 12)
            }
        }
        .frame(height: 42)
        .background(Color.cratesBg)
        .animation(.easeInOut(duration: 0.25), value: isAnalysing)
        .animation(.easeInOut(duration: 0.25), value: analysisToast)
    }

    // MARK: - Status readout

    @ViewBuilder
    private var statusArea: some View {
        if isAnalysing {
            HStack(spacing: 5) {
                ScanPulse()
                Text("SCANNING")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.cratesAccent)
                    .tracking(1.5)
            }
        } else if let toast = analysisToast {
            Text(toast)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(toast.contains("FAILED") ? .red.opacity(0.7) : .cratesLive)
                .tracking(1)
                .transition(.opacity)
        } else {
            HStack(spacing: 6) {
                if let range = bpmRange {
                    HStack(spacing: 2) {
                        Text(range)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.cratesDim)
                        Text("BPM")
                            .font(.system(size: 7, weight: .black, design: .monospaced))
                            .foregroundColor(.cratesGhost)
                            .tracking(1)
                    }
                    Text("·")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.cratesGhost)
                }
                HStack(spacing: 2) {
                    Text("\(crate.songs.count)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.cratesDim)
                    Text("TRK")
                        .font(.system(size: 7, weight: .black, design: .monospaced))
                        .foregroundColor(.cratesGhost)
                        .tracking(1)
                }
            }
        }
    }

    // MARK: - Column labels

    private var columnLabels: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 3) // aligns with the orange rail above
            Text("#")
                .frame(width: 44, alignment: .trailing)
            Color.clear.frame(width: 46)
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
        .font(.system(size: 8, weight: .black, design: .monospaced))
        .tracking(2)
        .foregroundColor(.cratesGhost)
        .frame(height: 26)
        .padding(.horizontal, 8)
        .background(Color.cratesSurface)
    }

    // MARK: - Name commit

    private func commitName() {
        let name = nameText.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { crateState.renameCrate(crate.id, name: name) }
        isEditingName = false
    }
}

// MARK: - Analyse button

private struct AnalyseButton: View {
    let isRunning: Bool
    let action:    () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isRunning {
                    ScanPulse()
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 7, weight: .bold))
                }
                Text(isRunning ? "SCANNING" : "ANALYSE")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .tracking(1.5)
            }
            .foregroundColor(
                isRunning ? .cratesAccent
                          : (hovered ? .cratesAccent : .cratesDim)
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                (hovered && !isRunning) ? Color.cratesAccent.opacity(0.07) : Color.clear
            )
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(
                        isRunning
                            ? Color.cratesAccent.opacity(0.35)
                            : (hovered ? Color.cratesAccent.opacity(0.35) : Color.cratesBorder),
                        lineWidth: 0.5
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .animation(.easeInOut(duration: 0.1), value: hovered)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

// MARK: - Intel button

private struct IntelButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 7, weight: .bold))
                Text("INTEL")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .tracking(1.5)
            }
            .foregroundColor(hovered ? .cratesKey : Color.cratesKey.opacity(0.7))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(hovered ? Color.cratesKey.opacity(0.12) : Color.cratesKey.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(
                        hovered ? Color.cratesKey.opacity(0.4) : Color.cratesKey.opacity(0.2),
                        lineWidth: 0.5
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .animation(.easeInOut(duration: 0.1), value: hovered)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

// MARK: - Scan pulse dot

private struct ScanPulse: View {
    @State private var scale = 1.0
    var body: some View {
        Circle()
            .fill(Color.cratesAccent)
            .frame(width: 4, height: 4)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                    scale = 1.9
                }
            }
    }
}

// MARK: - Empty crate

struct EmptyCrateView: View {
    var body: some View {
        VStack(spacing: 16) {
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
