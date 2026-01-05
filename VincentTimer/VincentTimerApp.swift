import SwiftUI

@main
struct VincentTimerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .background(Color.black)
                .frame(minWidth: 375, minHeight: 600)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 375, height: 600)
        .windowResizability(.contentMinSize)
    }
}
