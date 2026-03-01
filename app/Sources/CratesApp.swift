import SwiftUI

extension Notification.Name {
    static let openFolderPanel = Notification.Name("openFolderPanel")
}

@main
struct CratesApp: App {
    @StateObject private var crateState    = CrateState()
    @StateObject private var nowPlaying    = NowPlayingState()
    @StateObject private var chatViewModel = ChatViewModel()
    @StateObject private var folderWatcher = FolderWatcher()
    @StateObject private var audioPlayer   = AudioPlayer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(crateState)
                .environmentObject(nowPlaying)
                .environmentObject(chatViewModel)
                .environmentObject(folderWatcher)
                .environmentObject(audioPlayer)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1100, height: 640)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Import Folder…") {
                    // Post notification so ContentView can open the panel
                    NotificationCenter.default.post(name: .openFolderPanel, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}
