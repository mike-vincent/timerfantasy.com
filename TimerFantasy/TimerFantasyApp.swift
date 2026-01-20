import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Fix menu bar name to have a space
        if let mainMenu = NSApp.mainMenu,
           let appMenuItem = mainMenu.items.first {
            appMenuItem.title = "Timer Fantasy"
            // Also fix the submenu items that contain the app name
            if let submenu = appMenuItem.submenu {
                submenu.title = "Timer Fantasy"
                for item in submenu.items {
                    item.title = item.title.replacingOccurrences(of: "TimerFantasy", with: "Timer Fantasy")
                }
            }
        }
    }
}

@main
struct TimerFantasyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // 2 columns × 1 row with 200pt square cards + 8pt spacing
    private let initialWidth: CGFloat = 2 * 200 + 3 * 8  // 424
    private let initialHeight: CGFloat = 1 * 200 + 2 * 8 + 28  // 244 (28 for title bar)

    var body: some Scene {
        WindowGroup {
            ContentView()
                .background(Color.black)
        }
        .windowStyle(.automatic)
        .defaultSize(width: initialWidth, height: initialHeight)
    }
}
