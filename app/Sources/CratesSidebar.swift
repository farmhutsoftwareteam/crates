import SwiftUI
import UniformTypeIdentifiers

struct CratesSidebar: View {
    @EnvironmentObject var crateState: CrateState
    @State private var isCreating     = false
    @State private var newCrateName   = ""
    @State private var editingCrateId: UUID?
    @State private var isDropTargeted = false
    @FocusState private var createFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ───────────────────────────────────────────
            HStack {
                Text("CRATES")
                    .font(.system(size: 9, weight: .black))
                    .tracking(3)
                    .foregroundColor(.cratesDim)
                Spacer()
                // Open folder button
                Button {
                    openFolderPanel()
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 11))
                        .foregroundColor(.cratesDim)
                }
                .buttonStyle(.plain)
                .help("Import folder as crate")
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 8)

            // ── Crate list (drop target) ──────────────────────────
            ZStack {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(crateState.crates) { crate in
                            CrateRowView(
                                crate:      crate,
                                isSelected: crateState.activeCrateId == crate.id,
                                editingId:  $editingCrateId
                            )
                            .onTapGesture { crateState.activeCrateId = crate.id }
                            .contextMenu {
                                Button("Re-analyse Set") {
                                    reanalyseCrate(crate)
                                }
                                Divider()
                                Button("Rename") { editingCrateId = crate.id }
                                Button("Delete", role: .destructive) {
                                    crateState.deleteCrate(crate)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }

                // Drop-target overlay
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.cratesAccent, lineWidth: 2, antialiased: true)
                        .background(Color.cratesAccent.opacity(0.06).clipShape(RoundedRectangle(cornerRadius: 8)))
                        .overlay(
                            VStack(spacing: 6) {
                                Image(systemName: "folder.badge.plus")
                                    .font(.system(size: 24))
                                    .foregroundColor(.cratesAccent)
                                Text("IMPORT AS CRATE")
                                    .font(.system(size: 9, weight: .black))
                                    .tracking(2)
                                    .foregroundColor(.cratesAccent)
                            }
                        )
                        .padding(8)
                        .allowsHitTesting(false)
                }
            }
            .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers: providers)
            }

            Spacer(minLength: 0)

            Rectangle().fill(Color.cratesBorder).frame(height: 1)

            // ── Bottom actions ───────────────────────────────────
            if isCreating {
                HStack(spacing: 8) {
                    Text("🎵")
                    TextField("Set name…", text: $newCrateName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(.cratesPrimary)
                        .focused($createFocused)
                        .onSubmit { commitNewCrate() }
                    Button(action: commitNewCrate) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.cratesAccent)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .onAppear { createFocused = true }
            } else {
                HStack(spacing: 0) {
                    // New empty crate
                    Button {
                        newCrateName = ""
                        isCreating = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.cratesAccent)
                            Text("New Crate")
                                .font(.system(size: 12))
                                .foregroundColor(.cratesDim)
                        }
                        Spacer()
                    }
                    .buttonStyle(.plain)

                    // Open folder shortcut
                    Button {
                        openFolderPanel()
                    } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 11))
                            .foregroundColor(.cratesDim)
                    }
                    .buttonStyle(.plain)
                    .help("Import folder…")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .background(Color.cratesSurface)
        .onReceive(NotificationCenter.default.publisher(for: .openFolderPanel)) { _ in
            openFolderPanel()
        }
    }

    // MARK: - Re-analyse

    private func reanalyseCrate(_ crate: Crate) {
        if crate.folderPath != nil {
            crateState.reanalyseCrate(id: crate.id)
        } else {
            // Folder path unknown (crate pre-dates the folderPath field) — ask user
            let panel = NSOpenPanel()
            panel.canChooseFiles          = false
            panel.canChooseDirectories    = true
            panel.allowsMultipleSelection = false
            panel.message = "Point to the folder for \"\(crate.name)\" to run analysis"
            panel.prompt  = "Analyse"
            if panel.runModal() == .OK, let url = panel.url {
                crateState.reanalyseCrate(id: crate.id, overrideFolderURL: url)
            }
        }
    }

    // MARK: - Open panel

    private func openFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles          = false
        panel.canChooseDirectories    = true
        panel.allowsMultipleSelection = true
        panel.message = "Choose a folder (or folders) to import as crates"
        panel.prompt  = "Import"
        if panel.runModal() == .OK {
            for url in panel.urls {
                crateState.importFolder(url: url)
            }
        }
    }

    // MARK: - Drag-drop

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                guard let data = item as? Data,
                      let url  = URL(dataRepresentation: data, relativeTo: nil) else { return }
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                DispatchQueue.main.async {
                    if isDir.boolValue {
                        crateState.importFolder(url: url)
                    } else if FolderWatcher.audioExtensions.contains(url.pathExtension.lowercased()) {
                        // Single audio file drop → add to active crate
                        Task {
                            let meta = await AudioFileImporter.read(url: url)
                            let song = Song(title: meta.title, artist: meta.artist,
                                           bpm: meta.bpm, key: meta.key,
                                           durationMs: meta.durationMs, source: .manual)
                            crateState.addSong(song)
                            if meta.bpm == nil { crateState.enqueueBPMLookup(for: song) }
                        }
                    }
                }
                handled = true
            }
        }
        return handled
    }

    // MARK: - New crate

    private func commitNewCrate() {
        let t = newCrateName.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty { crateState.addCrate(name: t) }
        newCrateName = ""
        isCreating = false
    }
}

// MARK: - Crate row

struct CrateRowView: View {
    let crate:      Crate
    let isSelected: Bool
    @Binding var editingId: UUID?
    @EnvironmentObject var crateState: CrateState
    @State private var editText  = ""
    @State private var hovered   = false
    @FocusState private var editFocused: Bool

    var isEditing:   Bool { editingId == crate.id }
    var isImporting: Bool { crateState.importingCrateIds.contains(crate.id) }
    var isAnalysing: Bool { crateState.analysingCrateIds.contains(crate.id) }

    var body: some View {
        HStack(spacing: 0) {
            // Selection stripe
            Rectangle()
                .fill(isSelected ? Color.cratesAccent : Color.clear)
                .frame(width: 2)
                .clipShape(RoundedRectangle(cornerRadius: 1))

            HStack(spacing: 10) {
                Text(crate.emoji)
                    .font(.system(size: 15))

                VStack(alignment: .leading, spacing: 2) {
                    if isEditing {
                        TextField("", text: $editText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.cratesPrimary)
                            .focused($editFocused)
                            .onAppear { editText = crate.name; editFocused = true }
                            .onSubmit { commitRename() }
                    } else {
                        Text(crate.name)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                            .foregroundColor(isSelected ? .cratesPrimary : .cratesDim)
                            .lineLimit(1)
                    }

                    if isImporting || isAnalysing {
                        HStack(spacing: 5) {
                            ProgressView()
                                .progressViewStyle(.linear)
                                .scaleEffect(x: 1, y: 0.6)
                                .frame(width: 60)
                                .tint(Color.cratesAccent)
                            Text(isAnalysing ? "SCANNING…" : "IMPORTING…")
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                .tracking(0.5)
                                .foregroundColor(.cratesAccent.opacity(0.7))
                        }
                    } else {
                        Text("\(crate.songs.count) TRK")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(1)
                            .foregroundColor(.cratesGhost)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 10)
        }
        .frame(height: 48)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected
                      ? Color.cratesElevated
                      : (hovered ? Color.cratesElevated.opacity(0.5) : Color.clear))
        )
        .animation(.easeInOut(duration: 0.1), value: hovered)
        .onHover { hovered = $0 }
    }

    private func commitRename() {
        let t = editText.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty { crateState.renameCrate(crate.id, name: t) }
        editingId = nil
    }
}
