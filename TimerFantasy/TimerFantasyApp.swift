import SwiftUI
import AppKit
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Fix menu bar name to have a space
        if let mainMenu = NSApp.mainMenu,
           let appMenuItem = mainMenu.items.first {
            appMenuItem.title = "Timer Fantasy"
            if let submenu = appMenuItem.submenu {
                submenu.title = "Timer Fantasy"
                for item in submenu.items {
                    item.title = item.title.replacingOccurrences(of: "TimerFantasy", with: "Timer Fantasy")
                }
            }
        }
    }
}

// MARK: - Menu Bar State

class MenuBarState: ObservableObject {
    static let shared = MenuBarState()

    @AppStorage("menuBarShowText") var showText: Bool = true
    @Published var timers: [TimerModel] = []

    private var cancellables = Set<AnyCancellable>()
    private var updateTimer: Timer?

    private init() {
        // Load initial timers
        timers = TimerStore.shared.load()

        // Listen for timer changes
        NotificationCenter.default.publisher(for: .timersDidChange)
            .sink { [weak self] _ in
                self?.timers = TimerStore.shared.load()
            }
            .store(in: &cancellables)

        // Update every 0.5s for smooth countdown display
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    var primaryTimer: TimerModel? {
        timers.first
    }

    var hasRunningTimer: Bool {
        timers.contains { $0.timerState == .running || $0.timerState == .alarming }
    }

    var menuBarTitle: String {
        guard showText, let timer = primaryTimer else { return "" }

        switch timer.timerState {
        case .running, .paused:
            return formatTime(timer.timeRemaining)
        case .alarming:
            return "Done!"
        case .idle:
            return ""
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60

        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }
}


// MARK: - App

@main
struct TimerFantasyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var menuBarState = MenuBarState.shared

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

        // Menu bar extra
        MenuBarExtra {
            ForEach(menuBarState.timers) { timer in
                Section(timerName(timer)) {
                    // Time info
                    if let startTime = timer.startTime {
                        Text("Started at \(formatClockTime(startTime))")
                    }

                    if timer.useEndAtMode {
                        Text("Ends at \(formatEndAtTime(timer))")
                    } else {
                        Text("\(timer.initialTimeFormatted) countdown")
                    }

                    // Remaining time and status
                    Text("\(formatTime(timer.timeRemaining)) remaining")
                    Text(statusText(timer))

                    Divider()

                    if timer.timerState == .running {
                        Button("Pause") {
                            timer.pause()
                            saveTimers()
                        }
                    } else if timer.timerState == .paused {
                        Button("Resume") {
                            timer.resume()
                            saveTimers()
                        }
                        Button("Stop") {
                            timer.cancel()
                            saveTimers()
                        }
                    } else if timer.timerState == .alarming {
                        Button("Dismiss") {
                            timer.cancel()
                            saveTimers()
                        }
                    }
                }
            }

            if menuBarState.timers.isEmpty {
                Text("No timers")
            }

            Divider()

            Toggle("Show time in menu bar", isOn: $menuBarState.showText)

            Divider()

            Button("Open Timer Fantasy") {
                NSApp.activate(ignoringOtherApps: true)
                for window in NSApp.windows where window.canBecomeMain {
                    window.makeKeyAndOrderFront(nil)
                    break
                }
            }
            .keyboardShortcut("o")

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            HStack(spacing: 4) {
                Image(systemName: menuBarIcon)
                if menuBarState.showText && !menuBarState.menuBarTitle.isEmpty {
                    Text(menuBarState.menuBarTitle)
                        .monospacedDigit()
                }
            }
        }
    }

    private func timerName(_ timer: TimerModel) -> String {
        if timer.timerLabel.isEmpty || timer.timerLabel == "Timer" {
            return timer.defaultTimerName
        }
        return timer.timerLabel
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }

    private func statusText(_ timer: TimerModel) -> String {
        switch timer.timerState {
        case .running: return "Running"
        case .paused: return "Paused"
        case .alarming: return "Done!"
        case .idle: return "Idle"
        }
    }

    private func formatEndAtTime(_ timer: TimerModel) -> String {
        guard let endTime = timer.endTime else {
            // Fallback to stored end at values
            let hour = timer.endAtHour
            let minute = timer.endAtMinute
            let ampm = timer.endAtIsPM ? "PM" : "AM"
            return String(format: "%d:%02d %@", hour, minute, ampm)
        }
        return formatClockTime(endTime)
    }

    private func formatClockTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private func saveTimers() {
        TimerStore.shared.save(menuBarState.timers)
        NotificationCenter.default.post(name: .timersDidChange, object: nil)
    }

    private var menuBarIcon: String {
        guard let timer = menuBarState.primaryTimer else {
            return "timer"
        }

        switch timer.timerState {
        case .running:
            return "timer"
        case .paused:
            return "pause.circle.fill"
        case .alarming:
            return "bell.fill"
        case .idle:
            return "timer"
        }
    }
}
