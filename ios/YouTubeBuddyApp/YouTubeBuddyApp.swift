import SwiftUI

@main
struct YouTubeBuddyApp: App {
    @State private var settings = AppSettings.load()

    var body: some Scene {
        WindowGroup {
            PlayerView()
                .environment(settings)
        }
    }
}
