import SwiftUI

struct SongCard: View {
    let song:     Song
    let position: Int
    let crateId:  UUID
    @EnvironmentObject var crateState: CrateState

    @State private var hovered          = false
    @State private var isEditingNotes   = false
    @State private var notesText        = ""
    @State private var isEditingBPM     = false
    @State private var bpmText          = ""
    @State private var isEditingKey     = false
    @State private var keyText          = ""
    @State private var downloadState: DownloadState = .idle
    @FocusState private var notesFocused: Bool
    @FocusState private var bpmFocused: Bool
    @FocusState private var keyFocused: Bool

    var isLookingUp:  Bool { crateState.pendingLookups.contains(song.id) }
    var isAnalysing:  Bool { crateState.pendingAnalysis.contains(song.id) }
    var hasFailed:    Bool { crateState.analysisFailedIds.contains(song.id) }

    enum DownloadState { case idle, downloading, done, failed }

    var body: some View {
        HStack(spacing: 0) {
            // ── Left accent stripe ───────────────────────────────
            Rectangle()
                .fill(hovered ? Color.cratesAccent : Color.clear)
                .frame(width: 2)
                .animation(.easeInOut(duration: 0.1), value: hovered)

            HStack(spacing: 0) {
                // Position
                Text(String(format: "%02d", position))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(hovered ? Color.cratesAccent.opacity(0.7) : .cratesGhost)
                    .frame(width: 32, alignment: .trailing)
                    .animation(.easeInOut(duration: 0.1), value: hovered)

                Spacer().frame(width: 10)

                // Track avatar
                TrackAvatar(title: song.title, size: 28)

                Spacer().frame(width: 10)

                // Title + Artist
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.cratesPrimary)
                        .lineLimit(1)
                    Text(song.artist.isEmpty ? "—" : song.artist)
                        .font(.system(size: 10))
                        .foregroundColor(.cratesDim)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // ── BPM ──────────────────────────────────────────
                Group {
                    if isLookingUp && song.bpm == nil {
                        // Spinner while Claude is looking it up
                        ProgressView()
                            .progressViewStyle(.circular)
                            .controlSize(.mini)
                            .scaleEffect(0.7)
                            .frame(width: 54)
                    } else if isEditingBPM {
                        TextField("", text: $bpmText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundColor(.cratesAccent)
                            .multilineTextAlignment(.center)
                            .frame(width: 54)
                            .focused($bpmFocused)
                            .onSubmit     { commitBPM() }
                            .onExitCommand { isEditingBPM = false }
                    } else {
                        let bpmLabel = song.bpm.map { "\($0)" } ?? (isLookingUp ? "…" : "—")
                        Text(bpmLabel)
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundColor(song.bpm != nil ? .cratesAccent : .cratesGhost)
                            .frame(width: 54, alignment: .center)
                            .help("Click to edit BPM")
                            .onTapGesture {
                                bpmText = song.bpm.map { "\($0)" } ?? ""
                                isEditingBPM = true
                            }
                    }
                }

                // ── Key ──────────────────────────────────────────
                Group {
                    if isEditingKey {
                        TextField("", text: $keyText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.cratesKey)
                            .multilineTextAlignment(.center)
                            .frame(width: 48)
                            .focused($keyFocused)
                            .onSubmit     { commitKey() }
                            .onExitCommand { isEditingKey = false }
                    } else if let key = song.key {
                        Text(key)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.cratesKey)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.cratesKey.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .frame(width: 48, alignment: .center)
                            .help("Click to edit key")
                            .onTapGesture {
                                keyText = key
                                isEditingKey = true
                            }
                    } else {
                        Text(isLookingUp ? "…" : "—")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.cratesGhost)
                            .frame(width: 48, alignment: .center)
                            .help("Click to add Camelot key")
                            .onTapGesture {
                                keyText = ""
                                isEditingKey = true
                            }
                    }
                }

                // ── Energy bar ───────────────────────────────────
                EnergyBar(energy: song.energy, isAnalysing: isAnalysing, hasFailed: hasFailed)
                    .frame(width: 34, alignment: .center)

                // ── Notes ────────────────────────────────────────
                if isEditingNotes {
                    TextField("transition note…", text: $notesText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 10).italic())
                        .foregroundColor(.cratesDim)
                        .frame(width: 148, alignment: .leading)
                        .focused($notesFocused)
                        .onSubmit      { commitNotes() }
                        .onExitCommand { isEditingNotes = false }
                } else {
                    Text(song.notes.isEmpty ? (hovered ? "add note…" : "") : song.notes)
                        .font(.system(size: 10).italic())
                        .foregroundColor(song.notes.isEmpty ? .cratesGhost : Color(hex: "#484848"))
                        .frame(width: 148, alignment: .leading)
                        .lineLimit(1)
                        .onTapGesture {
                            notesText = song.notes
                            isEditingNotes = true
                        }
                }

                // ── Download / Find / Re-analyse actions ─────────
                if hovered {
                    HStack(spacing: 6) {
                        // Re-analyse
                        Button {
                            crateState.reanalyse(song: song)
                        } label: {
                            Group {
                                if isAnalysing {
                                    ProgressView()
                                        .controlSize(.mini)
                                        .frame(width: 22, height: 22)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.cratesDim)
                                        .frame(width: 22, height: 22)
                                }
                            }
                            .background(Color.cratesElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                        .disabled(isAnalysing)
                        .help("Re-analyse track (BPM, key, energy)")

                        // Download via yt-dlp (SoundCloud)
                        if DJPool.ytDlpPath != nil {
                            Button {
                                downloadTrack()
                            } label: {
                                downloadIcon
                            }
                            .buttonStyle(.plain)
                            .help("Download from SoundCloud via yt-dlp")
                        }

                        // Find on pool
                        Menu {
                            ForEach(DJPool.sources, id: \.name) { source in
                                Button(source.name) {
                                    openInBrowser(source.searchURL(song.title, song.artist))
                                }
                            }
                        } label: {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.cratesDim)
                                .frame(width: 22, height: 22)
                                .background(Color.cratesElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .frame(width: 22)
                        .help("Find on DJ pool")
                    }
                    .padding(.leading, 6)
                } else {
                    Spacer().frame(width: 22 + 6 + 22 + 6 + (DJPool.ytDlpPath != nil ? 22 + 6 : 0))
                }

                Spacer().frame(width: 10)
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 46)
        .background(hovered ? Color.cratesSurface : Color.cratesBg)
        .animation(.easeInOut(duration: 0.08), value: hovered)
        .onHover { hovered = $0 }
    }

    // MARK: - Actions

    private func commitBPM() {
        var updated = song
        updated.bpm = Int(bpmText.trimmingCharacters(in: .whitespaces))
        crateState.updateSong(updated, in: crateId)
        isEditingBPM = false
    }

    private func commitKey() {
        var updated = song
        let k = keyText.trimmingCharacters(in: .whitespaces)
        updated.key = k.isEmpty ? nil : k
        crateState.updateSong(updated, in: crateId)
        isEditingKey = false
    }

    private func commitNotes() {
        var updated = song
        updated.notes = notesText
        crateState.updateSong(updated, in: crateId)
        isEditingNotes = false
    }

    private func openInBrowser(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    private func downloadTrack() {
        downloadState = .downloading
        DJPool.downloadFromSoundCloud(title: song.title, artist: song.artist) { path in
            downloadState = path != nil ? .done : .failed
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { downloadState = .idle }
        }
    }

    // MARK: - Download icon

    @ViewBuilder
    private var downloadIcon: some View {
        let (icon, color): (String, Color) = {
            switch downloadState {
            case .idle:        return ("arrow.down", .cratesDim)
            case .downloading: return ("ellipsis", .cratesAccent)
            case .done:        return ("checkmark", .cratesLive)
            case .failed:      return ("xmark", .red)
            }
        }()
        Image(systemName: icon)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(color)
            .frame(width: 22, height: 22)
            .background(Color.cratesElevated)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Energy bar

/// 5-segment VU-meter style bar showing energy 0–10.
/// Shows a pulsing dot when librosa analysis is in progress.
struct EnergyBar: View {
    let energy:      Double?   // 0–10 or nil
    let isAnalysing: Bool
    let hasFailed:   Bool

    private let segments = 5
    private let heights: [CGFloat] = [5, 8, 11, 14, 17]

    var body: some View {
        if isAnalysing {
            Circle()
                .fill(Color.cratesAccent.opacity(0.5))
                .frame(width: 5, height: 5)
                .modifier(PulseModifier())
        } else if hasFailed {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9))
                .foregroundColor(.red.opacity(0.6))
                .help("Analysis failed — try Re-analyse from right-click menu")
        } else if let e = energy {
            let lit = Int((e / 10.0 * Double(segments)).rounded())
            HStack(spacing: 2) {
                ForEach(0..<segments, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(i < lit ? energyColor(e) : Color.cratesGhost)
                        .frame(width: 3, height: heights[i])
                }
            }
        } else {
            Color.clear
        }
    }

    private func energyColor(_ e: Double) -> Color {
        switch e {
        case ..<4:  return Color.cratesKey.opacity(0.8)
        case ..<7:  return Color.cratesAccent.opacity(0.9)
        default:    return Color.cratesAccent
        }
    }
}

private struct PulseModifier: ViewModifier {
    @State private var scale = 1.0
    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    scale = 1.8
                }
            }
    }
}
