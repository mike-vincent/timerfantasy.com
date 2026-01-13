import SwiftUI

@main
struct TimerFantasyApp: App {
    // 1 card with 2:1 aspect ratio (400x200) + 8pt spacing
    private let initialWidth: CGFloat = 400 + 2 * 8  // 416
    private let initialHeight: CGFloat = 200 + 2 * 8 + 28  // 244 (28 for title bar)

    var body: some Scene {
        WindowGroup {
            ContentView()
                .background(Color.black)
        }
        .windowStyle(.automatic)
        .defaultSize(width: initialWidth, height: initialHeight)
    }
}
