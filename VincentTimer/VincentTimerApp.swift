import SwiftUI

@main
struct VincentTimerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .background(VisualEffectBackground())
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 800, height: 600)
    }
}

#if os(macOS)
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .hudWindow
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
#else
struct VisualEffectBackground: View {
    var body: some View {
        Color.clear.background(.ultraThinMaterial)
    }
}
#endif
