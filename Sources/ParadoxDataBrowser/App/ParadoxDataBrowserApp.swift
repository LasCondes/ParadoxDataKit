#if os(macOS)
import SwiftUI

@main
struct ParadoxDataBrowserApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowToolbarStyle(.unifiedCompact)
    }
}
#endif
