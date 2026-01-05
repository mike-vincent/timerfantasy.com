import SwiftUI

@main
struct VincentTimerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .background(Color.black)
                .frame(minWidth: 360, minHeight: 640)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 360, height: 640)
        .windowResizability(.contentMinSize)
    }
}
