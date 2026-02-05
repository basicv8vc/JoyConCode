import SwiftUI

/// Main application entry point
@main
struct JoyConCodeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menubar-only app - no window needed
        // Using WindowGroup with empty content that's immediately hidden
        WindowGroup {
            EmptyView()
                .frame(width: 0, height: 0)
                .hidden()
        }
        .windowResizability(.contentSize)
    }

}
