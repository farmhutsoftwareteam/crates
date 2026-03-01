import SwiftUI

// MARK: - Song card

struct SongCard: View {
    let song:     Song
    let position: Int
    let crateId:  UUID
    @EnvironmentObject var crateState:  CrateState
    @EnvironmentObject var audioPlayer: AudioPlayer

    // Edit states
    @State private var hovered          = false
    @State private var isEditingNotes   = false
    @State private var notesText        = ""
    @State private var isEditingBPM     = false
    @State private var bpmText          = ""
    @State private var isEditingKey     = false
    @State private var keyText          = ""
    @State private var downloadState: DownloadState = .idle

    // Focus states — must be set alongside the editing flag to get keyboard focus
    @FocusState private var notesFocused: Bool
    @FocusState private var bpmFocused:   Bool
    @FocusState private var keyFocused:   Bool

    var isLookingUp: Bool { crateState.pendingLookups.contains(song.id) }
    var isAnalysing: Bool { crateState.pendingAnalysis.contains(song.id) }
    var hasFailed:   Bool { crateState.analysisFailedIds.contains(song.id) }

    // Is THIS song the one currently loaded in the shared player?
    var isThisPlaying: Bool {
        audioPlayer.currentSong?.id == song.id && audioPlayer.isPlaying
    }
    var isThisLoaded: Bool {
        audioPlayer.currentSong?.id == song.id
    }

    var hasLocalFile: Bool   { song.localFilePath != nil }
    var isSpotify:    Bool   { song.source == .spotify }
    var fileExt:      String? {
        guard let p = song.localFilePath else { return nil }
        let e = URL(fileURLWithPath: p).pathExtension.uppercased()
        return e.isEmpty ? nil : e
    }

    private var crateQueue: [Song] {
        crateState.crates.first(where: { $0.id == crateId })?.songs ?? []
    }

    enum DownloadState { case idle, downloading, done, failed }

    // MARK: - Stripe colour

    private var stripeColor: Color {
        if isThisPlaying          { return Color.cratesAccent }
        if hovered                { return Color.cratesAccent }
        if isSpotify              { return Color.cratesSpotify.opacity(0.5) }
        if hasLocalFile           { return Color.cratesAccent.opacity(0.28) }
        return Color.clear
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            // ── Left source stripe ───────────────────────────────
            Rectangle()
                .fill(stripeColor)
                .frame(width: 2)
                .animation(.easeInOut(duration: 0.12), value: hovered)

            HStack(spacing: 0) {
                // ── Position ──────────────────────────────────────
                Text(String(format: "%02d", position))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(positionColor)
                    .frame(width: 32, alignment: .trailing)
                    .animation(.easeInOut(duration: 0.1), value: hovered)

                Spacer().frame(width: 6)

                // ── Source slot (play / Spotify badge) ─────────
                sourceSlot
                    .frame(width: 22)

                Spacer().frame(width: 6)

                // ── Track avatar + source badge ───────────────
                TrackAvatar(title: song.title, size: 28)
                    .overlay(alignment: .bottomTrailing) { avatarBadge }

                Spacer().frame(width: 10)

                // ── Title + Artist ────────────────────────────
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.cratesPrimary)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(song.artist.isEmpty ? "—" : song.artist)
                            .font(.system(size: 10))
                            .foregroundColor(.cratesDim)
                            .lineLimit(1)
                        if isSpotify {
                            Text("SPOTIFY")
                                .font(.system(size: 7, weight: .black))
                                .tracking(0.5)
                                .foregroundColor(Color.cratesSpotify.opacity(0.8))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.cratesSpotify.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 2))
                        } else if let ext = fileExt {
                            Text(ext)
                                .font(.system(size: 7, weight: .black, design: .monospaced))
                                .foregroundColor(Color.cratesAccent.opacity(0.65))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.cratesAccent.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 2))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // ── BPM ──────────────────────────────────────────
                Group {
                    if isLookingUp && song.bpm == nil {
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
                        let label = song.bpm.map { "\($0)" } ?? (isLookingUp ? "…" : "—")
                        Text(label)
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
                        .contentShape(Rectangle())
                        .onTapGesture {
                            notesText = song.notes
                            isEditingNotes = true
                        }
                }

                // ── Hover actions ─────────────────────────────────
                if hovered {
                    HStack(spacing: 6) {
                        // Re-analyse
                        Button { crateState.reanalyse(song: song) } label: {
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
                        .help("Re-analyse track")

                        // Download via yt-dlp
                        if DJPool.ytDlpPath != nil {
                            Button { downloadTrack() } label: { downloadIcon }
                                .buttonStyle(.plain)
                                .help("Download from SoundCloud")
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
        .background(rowBackground)
        .animation(.easeInOut(duration: 0.08), value: hovered)
        .onHover { hovered = $0 }
        // ── Focus fixes: set focus state when editing begins ─────
        .onChange(of: isEditingNotes) { editing in if editing { notesFocused = true } }
        .onChange(of: isEditingBPM)   { editing in if editing { bpmFocused   = true } }
        .onChange(of: isEditingKey)   { editing in if editing { keyFocused   = true } }
    }

    // MARK: - Computed appearance

    private var rowBackground: Color {
        if isThisLoaded { return Color.cratesAccent.opacity(0.05) }
        return hovered ? Color.cratesSurface : Color.cratesBg
    }

    private var positionColor: Color {
        if hovered        { return Color.cratesAccent.opacity(0.7) }
        if isThisPlaying  { return Color.cratesAccent }
        if isThisLoaded   { return Color.cratesAccent.opacity(0.5) }
        if isSpotify      { return Color.cratesSpotify.opacity(0.6) }
        return .cratesGhost
    }

    // MARK: - Source slot (play button or Spotify indicator)

    @ViewBuilder
    private var sourceSlot: some View {
        if hasLocalFile {
            Button {
                if isThisLoaded {
                    audioPlayer.togglePlayPause()
                } else {
                    audioPlayer.play(song: song, in: crateQueue)
                }
            } label: {
                let icon = isThisPlaying ? "pause.fill" : "play.fill"
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(isThisLoaded ? Color.cratesAccent : (hovered ? Color.cratesDim : Color(hex: "#333333")))
                    .frame(width: 20, height: 20)
                    .background(
                        isThisLoaded
                            ? Color.cratesAccent.opacity(0.18)
                            : (hovered ? Color.cratesElevated : Color.clear)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .animation(.easeInOut(duration: 0.08), value: isThisPlaying)
            }
            .buttonStyle(.plain)
            .help(isThisPlaying ? "Pause" : "Play \(fileExt ?? "track")")
        } else if isSpotify {
            ZStack {
                Circle()
                    .fill(Color.cratesSpotify.opacity(0.14))
                    .frame(width: 17, height: 17)
                Text("S")
                    .font(.system(size: 8, weight: .black))
                    .foregroundColor(Color.cratesSpotify)
            }
            .help("Spotify track — no local file")
        } else {
            Color.clear
        }
    }

    // MARK: - Avatar badge

    @ViewBuilder
    private var avatarBadge: some View {
        if let ext = fileExt {
            Text(String(ext.prefix(3)))
                .font(.system(size: 5, weight: .black, design: .monospaced))
                .foregroundColor(Color.cratesAccent)
                .padding(.horizontal, 2)
                .padding(.vertical, 1)
                .background(Color(hex: "#0A0A0A"))
                .clipShape(RoundedRectangle(cornerRadius: 1))
                .offset(x: 5, y: 5)
        } else if isSpotify {
            Circle()
                .fill(Color.cratesSpotify)
                .frame(width: 6, height: 6)
                .offset(x: 2, y: 2)
        }
    }

    // MARK: - Note / BPM / Key commits

    private func commitNotes() {
        var updated = song
        updated.notes = notesText
        crateState.updateSong(updated, in: crateId)
        isEditingNotes = false
    }

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

    // MARK: - Other actions

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
            case .idle:        return ("arrow.down",  .cratesDim)
            case .downloading: return ("ellipsis",    .cratesAccent)
            case .done:        return ("checkmark",   .cratesLive)
            case .failed:      return ("xmark",       .red)
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
struct EnergyBar: View {
    let energy:      Double?
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
                .help("Analysis failed — right-click → Re-analyse")
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

struct PulseModifier: ViewModifier {
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
