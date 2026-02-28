import SwiftUI

struct NowPlayingBar: View {
    @EnvironmentObject var nowPlaying: NowPlayingState
    @EnvironmentObject var crateState: CrateState
    @State private var saveFlash = false
    @State private var pulsing   = false

    var isLive: Bool { nowPlaying.currentTrack?.isPlaying == true }

    var body: some View {
        HStack(spacing: 14) {
            // ── Live indicator ────────────────────────────────────
            ZStack {
                Circle()
                    .fill(isLive ? Color.cratesLive.opacity(0.18) : Color.clear)
                    .frame(width: 18, height: 18)
                    .scaleEffect(pulsing ? 1.5 : 1.0)
                Circle()
                    .fill(isLive ? Color.cratesLive : Color.cratesGhost)
                    .frame(width: 7, height: 7)
            }
            .animation(
                isLive
                    ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true)
                    : .default,
                value: pulsing
            )
            .onAppear { pulsing = isLive }
            .onChange(of: isLive) { pulsing = $0 }

            // ── Track info ───────────────────────────────────────
            if let track = nowPlaying.currentTrack {
                // Mini avatar
                TrackAvatar(title: track.title, size: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.cratesPrimary)
                        .lineLimit(1)
                    Text(track.artist.isEmpty ? "Unknown artist" : track.artist)
                        .font(.system(size: 11))
                        .foregroundColor(.cratesDim)
                        .lineLimit(1)
                }

                if isLive {
                    PlayingBars()
                        .frame(width: 18, height: 14)
                }

            } else {
                Text(nowPlaying.isCliAvailable ? "NOTHING PLAYING" : "INSTALL NOWPLAYING-CLI")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(.cratesDim)

                if !nowPlaying.isCliAvailable {
                    Text("brew install nowplaying-cli")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.cratesGhost)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.cratesBorder))
                }
            }

            Spacer()

            // ── SAVE button ──────────────────────────────────────
            if nowPlaying.currentTrack != nil {
                Button(action: save) {
                    HStack(spacing: 6) {
                        Image(systemName: saveFlash ? "checkmark" : "plus")
                            .font(.system(size: 10, weight: .black))
                        Text(saveFlash ? "SAVED" : "SAVE")
                            .font(.system(size: 10, weight: .black))
                            .tracking(1.5)
                    }
                    .foregroundColor(Color.cratesBg)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(saveFlash ? Color.cratesLive : Color.cratesAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .animation(.easeInOut(duration: 0.15), value: saveFlash)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(crateState.activeCrateId == nil)
            }
        }
        .padding(.horizontal, 16)
        .background(Color.cratesBg)
    }

    private func save() {
        guard let track = nowPlaying.currentTrack else { return }
        let song = Song(title: track.title, artist: track.artist)
        crateState.addSong(song)
        crateState.enqueueBPMLookup(for: song)
        saveFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { saveFlash = false }
    }
}

// MARK: - Animated playing bars (Rekordbox-style)

struct PlayingBars: View {
    @State private var phase = false
    private let heights: [CGFloat] = [8, 14, 6, 12, 10]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(heights.enumerated()), id: \.offset) { i, h in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.cratesAccent)
                    .frame(width: 2.5, height: phase ? h : 3)
                    .animation(
                        .easeInOut(duration: 0.35 + Double(i) * 0.08)
                        .repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.1),
                        value: phase
                    )
            }
        }
        .onAppear { phase = true }
    }
}
