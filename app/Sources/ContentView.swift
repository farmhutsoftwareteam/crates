import SwiftUI

struct ContentView: View {
    @EnvironmentObject var crateState:    CrateState
    @EnvironmentObject var nowPlaying:    NowPlayingState
    @EnvironmentObject var chatViewModel: ChatViewModel
    @EnvironmentObject var folderWatcher: FolderWatcher
    @EnvironmentObject var audioPlayer:   AudioPlayer
    @State private var chatOpen = false

    var body: some View {
        ZStack {
            Color.cratesBg.ignoresSafeArea()

            VStack(spacing: 0) {
                NowPlayingBar()
                    .frame(height: 56)

                Rectangle()
                    .fill(Color.cratesBorder)
                    .frame(height: 1)

                HStack(spacing: 0) {
                    // ── Sidebar ──────────────────────────────────
                    CratesSidebar()
                        .frame(width: 180)

                    Rectangle().fill(Color.cratesBorder).frame(width: 1)

                    // ── Set Intel — always visible ────────────────
                    if let id = crateState.activeCrateId,
                       let crate = crateState.crates.first(where: { $0.id == id }) {
                        SetIntelView(crate: crate)
                            .frame(width: 272)
                        Rectangle().fill(Color.cratesBorder).frame(width: 1)
                    }

                    // ── Main content ─────────────────────────────
                    ZStack(alignment: .bottomTrailing) {
                        Group {
                            if let id = crateState.activeCrateId,
                               let crate = crateState.crates.first(where: { $0.id == id }) {
                                SongListView(crate: crate)
                            } else {
                                EmptySetView()
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        // ASH open button — only visible when chat is closed
                        if !chatOpen {
                            AshButton {
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                    chatOpen = true
                                }
                            }
                            .padding(14)
                            .transition(.opacity.combined(with: .scale(scale: 0.85)))
                        }
                    }

                    // ── Chat panel ───────────────────────────────
                    if chatOpen {
                        HStack(spacing: 0) {
                            Rectangle().fill(Color.cratesBorder).frame(width: 1)
                            ChatView(onDismiss: {
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                    chatOpen = false
                                }
                            })
                            .frame(width: 300)
                        }
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal:   .move(edge: .trailing).combined(with: .opacity)
                        ))
                    }
                }

                // ── Player bar (persistent bottom transport) ──────
                Rectangle()
                    .fill(Color.cratesBorder)
                    .frame(height: 1)

                PlayerBar()
            }
        }
        .frame(minWidth: 820, minHeight: 540)
        // ── Import notifications (Downloads folder watcher) ──────
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(folderWatcher.pendingImports, id: \.absoluteString) { url in
                    ImportBanner(url: url)
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal:   .move(edge: .leading).combined(with: .opacity)
                        ))
                }
            }
            .padding(14)
            .animation(.spring(response: 0.35), value: folderWatcher.pendingImports.count)
        }
    }
}

// MARK: - ASH open button

struct AshButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.cratesLive)
                    .frame(width: 5, height: 5)
                Text("ASH")
                    .font(.system(size: 10, weight: .black))
                    .tracking(2)
                    .foregroundColor(Color.cratesBg)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(Color.cratesAccent)
            .clipShape(Capsule())
            .scaleEffect(hovered ? 1.06 : 1.0)
            .animation(.spring(response: 0.18), value: hovered)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

// MARK: - Empty state

struct EmptySetView: View {
    @EnvironmentObject var crateState: CrateState

    var body: some View {
        VStack(spacing: 18) {
            HStack(alignment: .center, spacing: 4) {
                ForEach([12, 22, 8, 30, 16, 26, 10, 20, 6, 28, 14], id: \.self) { h in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.cratesGhost)
                        .frame(width: 4, height: CGFloat(h))
                }
            }
            Text("NO CRATE SELECTED")
                .font(.system(size: 10, weight: .bold))
                .tracking(3)
                .foregroundColor(.cratesDim)
            Button("CREATE CRATE") { crateState.addCrate(name: "New Set") }
                .buttonStyle(AccentButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cratesBg)
    }
}
