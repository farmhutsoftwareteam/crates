import SwiftUI

// MARK: - Persistent bottom player bar

struct PlayerBar: View {
    @EnvironmentObject var audioPlayer: AudioPlayer

    var body: some View {
        HStack(spacing: 0) {
            // ── Track info (left, fixed) ─────────────────────────
            trackInfo
                .frame(width: 220, alignment: .leading)

            Rectangle().fill(Color.cratesBorder).frame(width: 1)
                .padding(.vertical, 12)

            // ── Transport + scrubber (centre, flex) ──────────────
            transport
                .frame(maxWidth: .infinity)

            Rectangle().fill(Color.cratesBorder).frame(width: 1)
                .padding(.vertical, 12)

            // ── Volume (right, fixed) ────────────────────────────
            volumeControl
                .frame(width: 120)
        }
        .frame(height: 56)
        .background(Color(hex: "#080808"))
    }

    // MARK: Track info

    private var trackInfo: some View {
        HStack(spacing: 10) {
            Spacer().frame(width: 4)

            if let song = audioPlayer.currentSong {
                TrackAvatar(title: song.title, size: 30)
                    .overlay(alignment: .bottomTrailing) {
                        if song.source == .spotify {
                            Circle().fill(Color.cratesSpotify).frame(width: 6, height: 6).offset(x: 2, y: 2)
                        } else if let ext = fileExt(song) {
                            Text(ext).font(.system(size: 5, weight: .black, design: .monospaced))
                                .foregroundColor(Color.cratesAccent)
                                .padding(.horizontal, 2).padding(.vertical, 1)
                                .background(Color(hex: "#080808"))
                                .clipShape(RoundedRectangle(cornerRadius: 1))
                                .offset(x: 5, y: 5)
                        }
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.cratesPrimary)
                        .lineLimit(1)
                    Text(song.artist.isEmpty ? "—" : song.artist)
                        .font(.system(size: 9))
                        .foregroundColor(.cratesDim)
                        .lineLimit(1)
                }

                // Queue position badge
                if audioPlayer.queueCount > 1 {
                    Text("\(audioPlayer.queuePos) / \(audioPlayer.queueCount)")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.cratesGhost)
                        .padding(.trailing, 6)
                }

            } else {
                // Empty state
                VStack(alignment: .leading, spacing: 3) {
                    Text("NO TRACK LOADED")
                        .font(.system(size: 9, weight: .black))
                        .tracking(2)
                        .foregroundColor(.cratesGhost)
                    Text("Click ▶ on any local track")
                        .font(.system(size: 9))
                        .foregroundColor(Color(hex: "#2A2A2A"))
                }
                .padding(.leading, 10)
            }
        }
    }

    // MARK: Transport + scrubber

    private var transport: some View {
        VStack(spacing: 6) {
            // Controls row
            HStack(spacing: 16) {
                Spacer()

                // Previous
                Button { audioPlayer.previous() } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(audioPlayer.hasPrevious ? .cratesDim : Color(hex: "#2A2A2A"))
                }
                .buttonStyle(.plain)
                .disabled(!audioPlayer.hasPrevious)
                .help("Previous track")

                // Play / Pause — larger, prominent
                Button { audioPlayer.togglePlayPause() } label: {
                    ZStack {
                        Circle()
                            .fill(audioPlayer.currentSong != nil ? Color.cratesAccent : Color(hex: "#1C1C1C"))
                            .frame(width: 28, height: 28)
                        Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(audioPlayer.currentSong != nil ? Color(hex: "#080808") : .cratesGhost)
                            .offset(x: audioPlayer.isPlaying ? 0 : 1)
                    }
                }
                .buttonStyle(.plain)
                .disabled(audioPlayer.currentSong == nil)
                .help(audioPlayer.isPlaying ? "Pause" : "Play")

                // Next
                Button { audioPlayer.next() } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(audioPlayer.hasNext ? .cratesDim : Color(hex: "#2A2A2A"))
                }
                .buttonStyle(.plain)
                .disabled(!audioPlayer.hasNext)
                .help("Next track")

                Spacer()
            }

            // Scrubber row
            HStack(spacing: 8) {
                Text(audioTimeString(audioPlayer.currentTime))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.cratesDim)
                    .frame(width: 34, alignment: .trailing)

                AudioScrubber(
                    progress: audioPlayer.progress,
                    isActive: audioPlayer.currentSong != nil
                ) { fraction in
                    audioPlayer.seek(to: fraction)
                }

                Text(audioTimeString(audioPlayer.duration))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.cratesDim)
                    .frame(width: 34, alignment: .leading)
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 8)
    }

    // MARK: Volume

    private var volumeControl: some View {
        HStack(spacing: 7) {
            Image(systemName: volumeIcon)
                .font(.system(size: 10))
                .foregroundColor(.cratesDim)
                .frame(width: 14)

            Slider(
                value: Binding(
                    get: { Double(audioPlayer.volume) },
                    set: { audioPlayer.setVolume(Float($0)) }
                ),
                in: 0...1
            )
            .controlSize(.mini)
            .tint(Color.cratesAccent)
            .frame(width: 72)

            Spacer().frame(width: 4)
        }
    }

    // MARK: Helpers

    private var volumeIcon: String {
        switch audioPlayer.volume {
        case 0:      return "speaker.slash.fill"
        case ..<0.4: return "speaker.wave.1.fill"
        case ..<0.7: return "speaker.wave.2.fill"
        default:     return "speaker.wave.3.fill"
        }
    }

    private func fileExt(_ song: Song) -> String? {
        guard let p = song.localFilePath else { return nil }
        let e = URL(fileURLWithPath: p).pathExtension.uppercased()
        return e.isEmpty ? nil : String(e.prefix(3))
    }
}

// MARK: - Scrubber

struct AudioScrubber: View {
    let progress: Double      // 0–1 from AudioPlayer
    let isActive: Bool
    let onSeek:   (Double) -> Void

    @State private var isDragging    = false
    @State private var dragProgress  = 0.0
    @State private var hovered       = false

    private var displayProgress: Double { isDragging ? dragProgress : progress }

    var body: some View {
        GeometryReader { geo in
            let w    = geo.size.width
            let fill = max(0, min(displayProgress * w, w))
            let trackH: CGFloat = (hovered || isDragging) ? 3 : 2

            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isActive ? Color.cratesGhost : Color(hex: "#1A1A1A"))
                    .frame(height: trackH)

                // Progress fill
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isActive ? Color.cratesAccent : Color(hex: "#2A2A2A"))
                    .frame(width: fill, height: trackH)

                // Thumb
                if (hovered || isDragging), isActive {
                    Circle()
                        .fill(Color.cratesAccent)
                        .frame(width: 10, height: 10)
                        .offset(x: max(0, fill - 5))
                        .shadow(color: Color.cratesAccent.opacity(0.4), radius: 4)
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        isDragging   = true
                        dragProgress = min(max(v.location.x / w, 0), 1)
                    }
                    .onEnded { v in
                        let p = min(max(v.location.x / w, 0), 1)
                        isDragging = false
                        if isActive { onSeek(p) }
                    }
            )
        }
        .frame(height: 16)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.1), value: hovered)
        .animation(.easeOut(duration: 0.1), value: isDragging)
    }
}
