import SwiftUI

@main
struct TranscriberMacApp: App {
    var body: some Scene {
        WindowGroup("TransLocalAI") {
            MacMainView()
        }
        .defaultSize(width: 760, height: 640)

        Settings {
            MacSettingsView()
        }
    }
}
