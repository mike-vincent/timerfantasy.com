import SwiftUI

@main
struct TimerFantasyApp: App {
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
