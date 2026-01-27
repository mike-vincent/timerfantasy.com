import AppIntents
import Foundation

// MARK: - Start Timer Intent

struct StartTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Timer"
    static var description = IntentDescription("Start a countdown timer in Timer Fantasy")

    @Parameter(title: "Duration", description: "Timer duration (e.g., '10 minutes', '1 hour 30 minutes')")
    var duration: Measurement<UnitDuration>

    @Parameter(title: "Timer Name", default: nil)
    var name: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Start a \(\.$duration) timer") {
            \.$name
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let seconds = duration.converted(to: .seconds).value
        guard seconds > 0 else {
            return .result(dialog: "Please specify a duration greater than zero.")
        }

        // Create and start the timer
        let timer = TimerModel()
        timer.selectedHours = Int(seconds) / 3600
        timer.selectedMinutes = (Int(seconds) % 3600) / 60
        timer.selectedSeconds = Int(seconds) % 60
        if let name = name, !name.isEmpty {
            timer.timerLabel = name
        }
        timer.start()

        // Save to store and notify UI
        await MainActor.run {
            var timers = TimerStore.shared.load()
            timers.append(timer)
            TimerStore.shared.save(timers)
            NotificationCenter.default.post(name: .timersDidChange, object: nil)
        }

        let formattedDuration = formatDuration(seconds)
        return .result(dialog: "Started \(formattedDuration) timer.")
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60

        var parts: [String] = []
        if h > 0 { parts.append("\(h) hour\(h == 1 ? "" : "s")") }
        if m > 0 { parts.append("\(m) minute\(m == 1 ? "" : "s")") }
        if s > 0 && h == 0 { parts.append("\(s) second\(s == 1 ? "" : "s")") }

        return parts.joined(separator: " ")
    }
}

// MARK: - App Shortcuts Provider

struct TimerFantasyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartTimerIntent(),
            phrases: [
                "Start a timer in \(.applicationName)",
                "Set a timer in \(.applicationName)",
                "Create a timer in \(.applicationName)"
            ],
            shortTitle: "Start Timer",
            systemImageName: "timer"
        )
    }
}
