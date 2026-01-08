import SwiftUI
import Combine
import AppKit

// MARK: - Persistable Timer Data
struct TimerData: Codable, Identifiable {
    let id: UUID
    var selectedHours: Int
    var selectedMinutes: Int
    var selectedSeconds: Int
    var timerState: String  // "idle", "running", "paused"
    var timeRemaining: TimeInterval
    var endTime: Date?
    var timerLabel: String
    var selectedAlarmSound: String
    var alarmDuration: Int
    var selectedClockface: String
    var initialSetSeconds: TimeInterval
    var isLooping: Bool
    var timerColorHex: String?  // Hex string for pie slice color
    var useAutoColor: Bool?
    var useAutoClockface: Bool?
    var useFlashWarning: Bool?
}

// MARK: - Color Hex Conversion
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: Double
        switch hex.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255
            g = Double((int >> 8) & 0xFF) / 255
            b = Double(int & 0xFF) / 255
        default:
            r = 1; g = 0.5; b = 0  // Default orange
        }
        self.init(red: r, green: g, blue: b)
    }

    var hexString: String {
        guard let components = NSColor(self).usingColorSpace(.sRGB) else { return "FF8000" }
        let r = Int(components.redComponent * 255)
        let g = Int(components.greenComponent * 255)
        let b = Int(components.blueComponent * 255)
        return String(format: "%02X%02X%02X", r, g, b)
    }
}

// MARK: - Timer Store (iCloud + UserDefaults persistence)
class TimerStore: ObservableObject {
    static let shared = TimerStore()
    private let iCloudKey = "com.timerfantasy.app.timers"
    private let userDefaultsKey = "TimerFantasyData"

    private init() {
        // Register for iCloud change notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(iCloudDidChange),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default
        )
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    @objc private func iCloudDidChange(_ notification: Notification) {
        // Notify that external data changed
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .timersDidChangeExternally, object: nil)
        }
    }

    func save(_ timers: [TimerModel]) {
        let data = timers.map { timer -> TimerData in
            TimerData(
                id: timer.id,
                selectedHours: timer.selectedHours,
                selectedMinutes: timer.selectedMinutes,
                selectedSeconds: timer.selectedSeconds,
                timerState: timer.timerState.rawValue,
                timeRemaining: timer.timeRemaining,
                endTime: timer.endTime,
                timerLabel: timer.timerLabel,
                selectedAlarmSound: timer.selectedAlarmSound,
                alarmDuration: timer.alarmDuration,
                selectedClockface: timer.selectedClockface.rawValue,
                initialSetSeconds: timer.initialSetSeconds,
                isLooping: timer.isLooping,
                timerColorHex: timer.timerColor.hexString,
                useAutoColor: timer.useAutoColor,
                useAutoClockface: timer.useAutoClockface,
                useFlashWarning: timer.useFlashWarning
            )
        }

        if let encoded = try? JSONEncoder().encode(data) {
            // Save to both iCloud and UserDefaults
            NSUbiquitousKeyValueStore.default.set(encoded, forKey: iCloudKey)
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }

    func load() -> [TimerModel] {
        // Try iCloud first, fall back to UserDefaults
        let data = NSUbiquitousKeyValueStore.default.data(forKey: iCloudKey)
            ?? UserDefaults.standard.data(forKey: userDefaultsKey)

        guard let data = data,
              let timerDataArray = try? JSONDecoder().decode([TimerData].self, from: data) else {
            return [TimerModel()]  // Return default timer if nothing saved
        }

        return timerDataArray.map { data -> TimerModel in
            let timer = TimerModel(id: data.id)
            timer.selectedHours = data.selectedHours
            timer.selectedMinutes = data.selectedMinutes
            timer.selectedSeconds = data.selectedSeconds
            timer.timerState = TimerModel.TimerState(rawValue: data.timerState) ?? .idle
            timer.timerLabel = data.timerLabel
            timer.selectedAlarmSound = data.selectedAlarmSound
            timer.alarmDuration = data.alarmDuration
            timer.selectedClockface = ClockfaceScale(rawValue: data.selectedClockface) ?? .minutes60
            timer.initialSetSeconds = data.initialSetSeconds
            timer.isLooping = data.isLooping
            if let hex = data.timerColorHex {
                timer.timerColor = Color(hex: hex)
            }
            if let useAutoColor = data.useAutoColor {
                timer.useAutoColor = useAutoColor
            }
            if let useAutoClockface = data.useAutoClockface {
                timer.useAutoClockface = useAutoClockface
            }
            if let useFlashWarning = data.useFlashWarning {
                timer.useFlashWarning = useFlashWarning
            }

            // Restore running timer based on endTime
            if timer.timerState == .running, let endTime = data.endTime {
                let remaining = endTime.timeIntervalSinceNow
                if remaining > 0 {
                    timer.timeRemaining = remaining
                    timer.endTime = endTime
                } else {
                    // Timer expired while app was closed
                    timer.timerState = .idle
                    timer.timeRemaining = 0
                    timer.endTime = nil
                }
            } else if timer.timerState == .paused {
                timer.timeRemaining = data.timeRemaining
                timer.endTime = nil
            } else if timer.timerState == .alarming {
                // Preserve endTime for alarming state (shows when alarm went off)
                timer.endTime = data.endTime
                timer.timeRemaining = 0
            } else {
                timer.timeRemaining = 0
                timer.endTime = nil
            }

            return timer
        }
    }
}

extension Notification.Name {
    static let timersDidChangeExternally = Notification.Name("timersDidChangeExternally")
}

// MARK: - Timer Model
class TimerModel: ObservableObject, Identifiable {
    let id: UUID
    @Published var selectedHours = 0
    @Published var selectedMinutes = 15
    @Published var selectedSeconds = 0
    @Published var timerState: TimerState = .idle
    @Published var timeRemaining: TimeInterval = 0
    @Published var endTime: Date?
    @Published var timerLabel: String = "Timer"
    @Published var selectedAlarmSound: String = "Glass (Default)"
    @Published var alarmDuration: Int = 5  // seconds (1-60)
    @Published var selectedClockface: ClockfaceScale = .minutes60
    @Published var initialSetSeconds: TimeInterval = 0  // Time originally set when started
    @Published var isAlarmRinging: Bool = false  // True while sound is playing
    @Published var isLooping: Bool = false  // Auto-restart when timer ends
    @Published var timerColor: Color = .orange  // Pie slice color (manual)
    @Published var useAutoColor: Bool = true  // Auto rainbow color based on time remaining
    @Published var useAutoClockface: Bool = true  // Auto-shrink watchface as time decreases
    @Published var useFlashWarning: Bool = true  // Flash in last 5%

    enum TimerState: String { case idle, running, paused, alarming }

    init(id: UUID = UUID()) {
        self.id = id
    }

    var totalSetSeconds: TimeInterval {
        TimeInterval(selectedHours * 3600 + selectedMinutes * 60 + selectedSeconds)
    }

    var initialTimeFormatted: String {
        let total = Int(initialSetSeconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }

    // Auto-select smallest watchface that fits remaining time
    var autoClockface: ClockfaceScale {
        ClockfaceScale.allCases.last { $0.seconds >= timeRemaining } ?? .hours96
    }

    // Effective clockface (auto or manual)
    var effectiveClockface: ClockfaceScale {
        useAutoClockface ? autoClockface : selectedClockface
    }

    // Effective color (auto or manual, with flash warning)
    var effectiveColor: Color {
        let baseColor = useAutoColor ? autoColor : timerColor

        // Flash in last 5% of current watchface
        if useFlashWarning {
            let clockfaceSeconds = effectiveClockface.seconds
            let percent = clockfaceSeconds > 0 ? timeRemaining / clockfaceSeconds : 1.0
            if percent < 0.05 {
                // Flash every 0.25 seconds
                let flash = Int(Date().timeIntervalSinceReferenceDate * 4) % 2 == 0
                return flash ? baseColor : Color.white
            }
        }

        return baseColor
    }

    // Urgency: red with increasing opacity as time runs out
    // Based on original timer duration, not watchface
    var autoColor: Color {
        guard initialSetSeconds > 0 else { return .red }
        let percent = timeRemaining / initialSetSeconds

        // Linear progression: ~50% opacity at halfway point
        let progress = 1.0 - percent

        // Opacity goes from 0.1 (full time) to 1.0 (no time)
        let opacity = 0.1 + progress * 0.9

        return Color.red.opacity(opacity)
    }

    func start() {
        guard totalSetSeconds > 0 else { return }
        initialSetSeconds = totalSetSeconds
        timeRemaining = totalSetSeconds
        endTime = Date().addingTimeInterval(totalSetSeconds)
        timerState = .running
        selectedClockface = ClockfaceScale.allCases.last { $0.seconds >= totalSetSeconds } ?? .hours96
    }

    func pause() { timerState = .paused }

    func resume() {
        endTime = Date().addingTimeInterval(timeRemaining)
        timerState = .running
    }

    func cancel() {
        timerState = .idle
        timeRemaining = 0
        endTime = nil
    }

    private var currentSound: NSSound?

    func update() {
        guard timerState == .running, let end = endTime else { return }
        let remaining = end.timeIntervalSinceNow
        if remaining <= 0 {
            timeRemaining = 0
            playAlarmSound()
            if isLooping {
                // Auto-restart with original time
                timeRemaining = initialSetSeconds
                endTime = Date().addingTimeInterval(initialSetSeconds)
                // Stay in running state
            } else {
                timerState = .alarming
            }
        } else {
            timeRemaining = remaining
        }
    }

    func playAlarmSound() {
        // Skip if No Sound selected
        if selectedAlarmSound == "No Sound" {
            isAlarmRinging = false
            return
        }

        // Extract sound name without "(Default)" suffix
        let soundName = selectedAlarmSound.replacingOccurrences(of: " (Default)", with: "")
        isAlarmRinging = true

        // Try to play from system sounds, loop for 5 seconds
        if let sound = NSSound(named: NSSound.Name(soundName)) {
            currentSound = sound
            sound.loops = true
            sound.play()

            // Stop sound after alarmDuration seconds but keep showing bell
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(alarmDuration)) { [weak self] in
                self?.currentSound?.stop()
                self?.isAlarmRinging = false
            }
        } else {
            // Fallback to system beep
            NSSound.beep()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.isAlarmRinging = false
            }
        }
    }

    func dismissAlarm() {
        currentSound?.stop()
        currentSound = nil
        isAlarmRinging = false
        timerState = .idle
    }
}

// MARK: - Clockface Scale (top level)
enum ClockfaceScale: String, CaseIterable {
    case hours96, hours72, hours48, hours24, hours16, hours12, hours8, hours4, minutes120, minutes90, minutes60, minutes30, minutes15, minutes9, minutes5, seconds60

    var seconds: Double {
        switch self {
        case .hours96: return 96 * 3600
        case .hours72: return 72 * 3600
        case .hours48: return 48 * 3600
        case .hours24: return 24 * 3600
        case .hours16: return 16 * 3600
        case .hours12: return 12 * 3600
        case .hours8: return 8 * 3600
        case .hours4: return 4 * 3600
        case .minutes120: return 120 * 60
        case .minutes90: return 90 * 60
        case .minutes60: return 60 * 60
        case .minutes30: return 30 * 60
        case .minutes15: return 15 * 60
        case .minutes9: return 9 * 60
        case .minutes5: return 5 * 60
        case .seconds60: return 60
        }
    }

    var label: String {
        switch self {
        case .hours96: return "96h"
        case .hours72: return "72h"
        case .hours48: return "48h"
        case .hours24: return "24h"
        case .hours16: return "16h"
        case .hours12: return "12h"
        case .hours8: return "8h"
        case .hours4: return "4h"
        case .minutes120: return "120m"
        case .minutes90: return "90m"
        case .minutes60: return "60m"
        case .minutes30: return "30m"
        case .minutes15: return "15m"
        case .minutes9: return "9m"
        case .minutes5: return "5m"
        case .seconds60: return "60s"
        }
    }
}

// MARK: - Main View
struct ContentView: View {
    @State private var timers: [TimerModel] = []
    @State private var saveTimer: AnyCancellable?
    @State private var draggingTimer: TimerModel?
    let globalTimer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    private let spacing: CGFloat = 8
    private let columnCount = 2
    private let baseCardSize: CGFloat = 200

    private var rowCount: Int {
        Int(ceil(Double(max(1, timers.count)) / Double(columnCount)))
    }

    private func saveTimers() {
        TimerStore.shared.save(timers)
    }

    private func bestGridLayout(itemCount: Int, windowRatio: Double) -> (cols: Int, rows: Int) {
        var bestCols = 1
        var bestRows = itemCount
        var bestRatioDiff = Double.infinity

        for testCols in 1...itemCount {
            let testRows = Int(ceil(Double(itemCount) / Double(testCols)))
            let gridRatio = Double(testCols) / Double(testRows)
            let diff = abs(gridRatio - windowRatio)
            if diff < bestRatioDiff {
                bestRatioDiff = diff
                bestCols = testCols
                bestRows = testRows
            }
        }
        return (bestCols, bestRows)
    }

    private func setupWindow() {
        guard let window = NSApplication.shared.windows.first else { return }
        // Allow completely free resizing
        window.resizeIncrements = NSSize(width: 1, height: 1)
        // Minimum size for one card
        window.minSize = NSSize(width: baseCardSize + spacing * 2, height: baseCardSize + spacing * 2 + 28)
    }

    var body: some View {
        GeometryReader { geo in
            let allItems = max(1, timers.count)
            let windowRatio = geo.size.width / geo.size.height
            let layout = bestGridLayout(itemCount: allItems, windowRatio: windowRatio)
            let actualCols = layout.cols
            let actualRows = layout.rows

            // Card size to fill available space based on actual grid dimensions
            let availableWidth = geo.size.width - spacing * CGFloat(actualCols + 1)
            let availableHeight = geo.size.height - spacing * CGFloat(actualRows + 1)
            let cardSize = min(availableWidth / CGFloat(actualCols), availableHeight / CGFloat(actualRows))

            let actualGridWidth = CGFloat(actualCols) * cardSize + CGFloat(actualCols - 1) * spacing
            let actualGridHeight = CGFloat(actualRows) * cardSize + CGFloat(actualRows - 1) * spacing

            VStack(spacing: spacing) {
                ForEach(0..<actualRows, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(0..<actualCols, id: \.self) { col in
                            let index = row * actualCols + col
                            if index < timers.count {
                                let timer = timers[index]
                                TimerCardView(timer: timer, compact: true, size: cardSize, onDelete: timers.count > 1 ? {
                                    _ = withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        timers.remove(at: index)
                                    }
                                    saveTimers()
                                } : nil, onAdd: {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        timers.append(TimerModel())
                                    }
                                    saveTimers()
                                })
                                .frame(width: cardSize, height: cardSize)
                                .transition(.scale.combined(with: .opacity))
                                .opacity(draggingTimer?.id == timer.id ? 0.5 : 1)
                                .onDrag {
                                    draggingTimer = timer
                                    return NSItemProvider(object: timer.id.uuidString as NSString)
                                }
                                .onDrop(of: [.text], delegate: TimerDropDelegate(
                                    timer: timer,
                                    timers: $timers,
                                    draggingTimer: $draggingTimer,
                                    onReorder: saveTimers
                                ))
                            } else {
                                // Invisible placeholder to complete the row
                                Color.clear
                                    .frame(width: cardSize, height: cardSize)
                            }
                        }
                    }
                }
            }
            .frame(width: actualGridWidth, height: actualGridHeight)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // Load saved timers
            timers = TimerStore.shared.load()
            if timers.isEmpty {
                timers = [TimerModel()]
            }
            setupWindow()
        }
        .onReceive(globalTimer) { _ in
            for timer in timers {
                timer.update()
            }
            // Save periodically (every update cycle)
            saveTimers()
        }
    }
}

// MARK: - Timer Drop Delegate
struct TimerDropDelegate: DropDelegate {
    let timer: TimerModel
    @Binding var timers: [TimerModel]
    @Binding var draggingTimer: TimerModel?
    let onReorder: () -> Void

    func performDrop(info: DropInfo) -> Bool {
        draggingTimer = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let dragging = draggingTimer,
              dragging.id != timer.id,
              let fromIndex = timers.firstIndex(where: { $0.id == dragging.id }),
              let toIndex = timers.firstIndex(where: { $0.id == timer.id }) else { return }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            timers.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
        }
        onReorder()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

// MARK: - Recent Timer Model
struct RecentTimer: Identifiable, Equatable {
    let id = UUID()
    let hours: Int
    let minutes: Int
    let seconds: Int

    var totalSeconds: TimeInterval {
        TimeInterval(hours * 3600 + minutes * 60 + seconds)
    }

    var displayTime: String {
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    var subtitle: String {
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours) hr") }
        if minutes > 0 { parts.append("\(minutes) min") }
        if seconds > 0 && hours == 0 { parts.append("\(seconds) sec") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Timer Card View
struct TimerCardView: View {
    @ObservedObject var timer: TimerModel
    var compact: Bool = false
    var size: CGFloat = 200  // Card size for proportional scaling
    var onDelete: (() -> Void)? = nil
    var onAdd: (() -> Void)? = nil

    private var scale: CGFloat { size / 200 }  // Base size is 200

    let alarmSounds = [
        "No Sound", "Glass (Default)", "Basso", "Blow", "Bottle", "Frog", "Funk",
        "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"
    ]

    var availableClockfaces: [ClockfaceScale] {
        // Allow clockfaces that fit the remaining time (so you can zoom in as timer counts down)
        ClockfaceScale.allCases.filter { $0.seconds >= timer.timeRemaining }
    }

    func cycleClockface() {
        let available = availableClockfaces
        guard !available.isEmpty else { return }
        if let currentIndex = available.firstIndex(of: timer.selectedClockface) {
            let nextIndex = (currentIndex + 1) % available.count
            timer.selectedClockface = available[nextIndex]
        } else {
            timer.selectedClockface = available.last ?? .hours24
        }
    }

    @FocusState private var focusedField: TimeField?
    @State private var showDeleteConfirmation = false
    @State private var showCancelConfirmation = false
    @State private var labelBeforeEdit: String = ""
    @State private var showEndAtPicker = false
    @State private var selectedEndTime = Date()
    @State private var isEditingLabel = false

    enum TimeField: Hashable {
        case hours, minutes, seconds, label
    }

    var rightButtonLabel: String {
        switch timer.timerState {
        case .idle, .paused: return "Start"
        case .running: return "Pause"
        case .alarming: return ""
        }
    }

    var rightButtonColor: Color {
        switch timer.timerState {
        case .idle, .paused: return .green
        case .running: return .blue
        case .alarming: return .red
        }
    }

    func toggleTimer() {
        switch timer.timerState {
        case .idle: timer.start()
        case .running: timer.pause()
        case .paused: timer.resume()
        case .alarming: timer.dismissAlarm()
        }
    }

    func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(ceil(duration))
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%02d:%02d", m, s)
        }
    }

    func getEndTimeString() -> String {
        guard let end = timer.endTime else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: end)
    }

    func copyTimerAsMarkdown() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd h:mm a"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"

        var md = "## \(timer.timerLabel)\n\n"

        // Calculate when timer was started
        if let end = timer.endTime {
            let startTime = end.addingTimeInterval(-timer.initialSetSeconds)
            md += "- **Started:** \(dateFormatter.string(from: startTime))\n"
        }

        md += "- **Duration:** \(timer.initialTimeFormatted)\n"
        md += "- **Remaining:** \(formatDuration(timer.timeRemaining))\n"

        if let end = timer.endTime {
            md += "- **Ends at:** \(timeFormatter.string(from: end))\n"
        }

        md += "- **Status:** \(timer.timerState == .running ? "Running" : "Paused")\n"

        // Alarm settings
        let soundName = timer.selectedAlarmSound.replacingOccurrences(of: " (Default)", with: "")
        md += "- **Alarm:** \(soundName) for \(timer.alarmDuration)s\n"

        if timer.isLooping {
            md += "- **Looping:** Yes\n"
        }

        // Timestamp of export
        md += "\n*Exported \(dateFormatter.string(from: Date()))*\n"

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(md, forType: .string)
    }

    func setTimeFromSeconds(_ seconds: Double) {
        timer.timeRemaining = max(1, seconds)
        let total = Int(seconds)
        timer.selectedHours = total / 3600
        timer.selectedMinutes = (total % 3600) / 60
        timer.selectedSeconds = total % 60
    }

    var body: some View {
        let clockSize = size * 0.5
        let digitFontSize = size * 0.16
        let countdownFontSize = size * 0.12
        let buttonFontSize = size * 0.04
        let buttonWidth = size * 0.20
        let buttonHeight = size * 0.09
        let cornerRadius = size * 0.06
        let padding = size * 0.04

        ZStack {
            // Main content centered
            VStack(spacing: size * 0.02) {
                if timer.timerState == .idle {
                    // Clickable digits
                    HStack(spacing: 0) {
                        TimeDigitField(value: $timer.selectedHours, maxValue: 168, isFocused: focusedField == .hours, size: size * 0.22, onSubmit: { timer.start() })
                            .focused($focusedField, equals: .hours)
                        Text(":")
                            .font(.system(size: digitFontSize, weight: .thin))
                            .foregroundStyle(.white)
                            .frame(width: size * 0.05)
                            .transition(.opacity.combined(with: .scale))
                        TimeDigitField(value: $timer.selectedMinutes, maxValue: 99, isFocused: focusedField == .minutes, size: size * 0.22, onSubmit: { timer.start() })
                            .focused($focusedField, equals: .minutes)
                        Text(":")
                            .font(.system(size: digitFontSize, weight: .thin))
                            .foregroundStyle(.white)
                            .frame(width: size * 0.05)
                            .transition(.opacity.combined(with: .scale))
                        TimeDigitField(value: $timer.selectedSeconds, maxValue: 99, isFocused: focusedField == .seconds, size: size * 0.22, onSubmit: { timer.start() })
                            .focused($focusedField, equals: .seconds)
                    }

                    // Options - compact circles in row
                    HStack(spacing: size * 0.02) {
                        let circleSize = size * 0.10

                        // Sound picker
                        Menu {
                            ForEach(alarmSounds, id: \.self) { sound in
                                Button(sound) {
                                    timer.selectedAlarmSound = sound
                                    if sound != "No Sound" {
                                        let soundName = sound.replacingOccurrences(of: " (Default)", with: "")
                                        if let s = NSSound(named: NSSound.Name(soundName)) {
                                            s.play()
                                        }
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: timer.selectedAlarmSound == "No Sound" ? "speaker.slash" : "speaker.wave.2")
                                .font(.system(size: size * 0.04))
                                .foregroundStyle(.white.opacity(0.7))
                                .frame(width: circleSize, height: circleSize)
                                .background(Circle().fill(Color(white: 0.2)))
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)

                        // Duration picker
                        Menu {
                            ForEach([1, 2, 3, 5, 10, 15, 30, 60], id: \.self) { seconds in
                                Button("\(seconds)s") {
                                    timer.alarmDuration = seconds
                                }
                            }
                        } label: {
                            Text("\(timer.alarmDuration)s")
                                .font(.system(size: size * 0.04, weight: .medium))
                                .foregroundStyle(.white.opacity(0.7))
                                .frame(width: circleSize, height: circleSize)
                                .background(Circle().fill(Color(white: 0.2)))
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)

                        // Loop toggle
                        Button(action: { timer.isLooping.toggle() }) {
                            Image(systemName: "repeat")
                                .font(.system(size: size * 0.04))
                                .foregroundStyle(timer.isLooping ? .red : .white.opacity(0.7))
                                .frame(width: circleSize, height: circleSize)
                                .background(Circle().fill(timer.isLooping ? Color.red.opacity(0.2) : Color(white: 0.2)))
                        }
                        .buttonStyle(.plain)

                        // End At picker
                        Button(action: {
                            selectedEndTime = Date().addingTimeInterval(3600)
                            showEndAtPicker = true
                        }) {
                            Image(systemName: "clock")
                                .font(.system(size: size * 0.04))
                                .foregroundStyle(.white.opacity(0.7))
                                .frame(width: circleSize, height: circleSize)
                                .background(Circle().fill(Color(white: 0.2)))
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showEndAtPicker) {
                            VStack(spacing: 12) {
                                Text("End At")
                                    .font(.headline)
                                DatePicker("", selection: $selectedEndTime, displayedComponents: .hourAndMinute)
                                    .datePickerStyle(.stepperField)
                                    .labelsHidden()
                                Button("Set") {
                                    let duration = selectedEndTime.timeIntervalSinceNow
                                    if duration > 0 {
                                        let total = Int(duration)
                                        timer.selectedHours = total / 3600
                                        timer.selectedMinutes = (total % 3600) / 60
                                        timer.selectedSeconds = total % 60
                                    }
                                    showEndAtPicker = false
                                    focusedField = nil
                                    NSApp.keyWindow?.makeFirstResponder(nil)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .padding()
                            .frame(width: 200)
                        }
                    }
                } else if timer.timerState == .alarming {
                    // Alarming: show bell with end time below, tap to dismiss
                    VStack(spacing: size * 0.02) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: size * 0.3))
                            .foregroundStyle(.red)
                            .symbolEffect(.pulse, options: .repeating, isActive: timer.isAlarmRinging)

                        // End time hung below bell
                        HStack(spacing: size * 0.01) {
                            Image(systemName: "bell.fill")
                                .font(.system(size: size * 0.025))
                            Text(getEndTimeString())
                                .font(.system(size: size * 0.035, weight: .medium))
                        }
                        .foregroundStyle(.white.opacity(0.5))

                        // Repeat button
                        Button(action: {
                            timer.dismissAlarm()
                            timer.timeRemaining = timer.initialSetSeconds
                            timer.endTime = Date().addingTimeInterval(timer.initialSetSeconds)
                            timer.timerState = .running
                        }) {
                            HStack(spacing: size * 0.01) {
                                Image(systemName: "repeat")
                                    .font(.system(size: size * 0.03))
                                Text("Repeat")
                                    .font(.system(size: size * 0.04, weight: .medium))
                            }
                            .foregroundStyle(.red)
                            .padding(.horizontal, size * 0.04)
                            .padding(.vertical, size * 0.02)
                            .background(Color.red.opacity(0.2))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .onTapGesture {
                        timer.dismissAlarm()
                    }
                } else {
                    // Running/Paused: clock centered with bell time hung below
                    ZStack {
                        AnalogTimerView(
                            remainingSeconds: timer.timeRemaining,
                            clockfaceSeconds: timer.effectiveClockface.seconds,
                            pieColor: timer.effectiveColor,
                            onSetTime: { seconds in
                                timer.timeRemaining = max(1, seconds)
                                timer.endTime = Date().addingTimeInterval(seconds)
                            }
                        )
                        .frame(width: clockSize, height: clockSize)

                        // Initial set time - inside clock face
                        Text(timer.initialTimeFormatted)
                            .font(.system(size: clockSize * 0.07, weight: .medium))
                            .foregroundStyle(.black.opacity(0.5))
                            .offset(y: clockSize * 0.12)

                        // Bell, countdown, and controls - hung below clock
                        VStack(spacing: size * 0.025) {
                            // Bell with end time
                            HStack(spacing: size * 0.015) {
                                Image(systemName: timer.selectedAlarmSound == "No Sound" ? "bell.slash.fill" : "bell.fill")
                                    .font(.system(size: size * 0.03))
                                Text(getEndTimeString())
                                    .font(.system(size: size * 0.04, weight: .medium))
                            }
                            .foregroundStyle(.white.opacity(0.5))

                            // Countdown
                            Text(formatDuration(timer.timeRemaining))
                                .font(.system(size: size * 0.08, weight: .bold))
                                .foregroundStyle(.white)

                            // Sound, Duration, Loop controls
                            HStack(spacing: size * 0.04) {
                                let circleSize = size * 0.10

                                // Sound picker
                                Menu {
                                    ForEach(alarmSounds, id: \.self) { sound in
                                        Button(sound) {
                                            timer.selectedAlarmSound = sound
                                            if sound != "No Sound" {
                                                let soundName = sound.replacingOccurrences(of: " (Default)", with: "")
                                                if let s = NSSound(named: NSSound.Name(soundName)) {
                                                    s.play()
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    Image(systemName: timer.selectedAlarmSound == "No Sound" ? "speaker.slash" : "speaker.wave.2")
                                        .font(.system(size: size * 0.045))
                                        .foregroundStyle(.white.opacity(0.7))
                                        .frame(width: circleSize, height: circleSize)
                                        .background(Circle().fill(Color(white: 0.2)))
                                }
                                .menuStyle(.borderlessButton)
                                .menuIndicator(.hidden)

                                // Duration picker
                                Menu {
                                    ForEach([1, 2, 3, 5, 10, 15, 30, 60], id: \.self) { seconds in
                                        Button("\(seconds)s") {
                                            timer.alarmDuration = seconds
                                        }
                                    }
                                } label: {
                                    Text("\(timer.alarmDuration)s")
                                        .font(.system(size: size * 0.042, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.7))
                                        .frame(width: circleSize, height: circleSize)
                                        .background(Circle().fill(Color(white: 0.2)))
                                }
                                .menuStyle(.borderlessButton)
                                .menuIndicator(.hidden)

                                // Loop toggle
                                Button(action: { timer.isLooping.toggle() }) {
                                    Image(systemName: "repeat")
                                        .font(.system(size: size * 0.045))
                                        .foregroundStyle(timer.isLooping ? .red : .white.opacity(0.7))
                                        .frame(width: circleSize, height: circleSize)
                                        .background(Circle().fill(timer.isLooping ? Color.red.opacity(0.2) : Color(white: 0.2)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .offset(y: clockSize * 0.62)
                    }
                }
            }

            // Top row: clockface toggle and label (left) - only when running/paused
            if timer.timerState == .running || timer.timerState == .paused {
                VStack {
                    HStack {
                        // Clockface toggle and label - top left, stacked
                        VStack(alignment: .leading, spacing: size * 0.01) {
                            Button(action: {
                                if !timer.useAutoClockface {
                                    cycleClockface()
                                }
                            }) {
                                Text("\(timer.effectiveClockface.label) Watchface")
                                    .font(.system(size: size * 0.035, weight: .medium))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, size * 0.04)
                                    .padding(.vertical, size * 0.02)
                                    .background(Color(white: 0.2))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)

                            TextField("Timer", text: $timer.timerLabel)
                                .font(.system(size: size * 0.035, weight: .medium))
                                .foregroundStyle(.white.opacity(0.8))
                                .textFieldStyle(.plain)
                                .frame(width: size * 0.35)
                                .padding(.horizontal, size * 0.04)
                                .padding(.vertical, size * 0.02)
                                .background(Color(white: 0.2))
                                .clipShape(Capsule())
                        }
                        Spacer()
                    }
                    Spacer()
                }
                .padding(padding)
            }

            // Bottom buttons - Delete/Cancel left, Start/Pause right (hide when alarming)
            if timer.timerState != .alarming {
                VStack {
                    Spacer()
                    HStack {
                        Button(action: {
                            if timer.timerState == .idle {
                                showDeleteConfirmation = true
                            } else {
                                showCancelConfirmation = true
                            }
                        }) {
                            Text(timer.timerState == .idle ? "Delete" : "Cancel")
                                .font(.system(size: buttonFontSize, weight: .medium))
                                .foregroundStyle(timer.timerState == .idle && onDelete == nil ? .gray : .red)
                                .frame(width: buttonWidth, height: buttonHeight)
                                .background(Color.red.opacity(timer.timerState == .idle && onDelete == nil ? 0.1 : 0.3))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(timer.timerState == .idle && onDelete == nil)

                        Spacer()

                        Button(action: toggleTimer) {
                            Text(rightButtonLabel)
                                .font(.system(size: buttonFontSize, weight: .medium))
                                .foregroundStyle(timer.timerState == .idle && timer.totalSetSeconds == 0 ? .gray : rightButtonColor)
                                .frame(width: buttonWidth, height: buttonHeight)
                                .background(rightButtonColor.opacity(timer.timerState == .idle && timer.totalSetSeconds == 0 ? 0.1 : 0.3))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(timer.timerState == .idle && timer.totalSetSeconds == 0)
                    }
                }
                .padding(padding)
                .confirmationDialog("Delete Timer?", isPresented: $showDeleteConfirmation) {
                    Button("Delete") {
                        onDelete?()
                    }
                    Button("Keep", role: .cancel) {}
                }
                .confirmationDialog("Cancel Timer?", isPresented: $showCancelConfirmation) {
                    Button("Cancel Timer") {
                        timer.cancel()
                    }
                    Button("Keep Running", role: .cancel) {}
                }
            }
        }
        .frame(width: size, height: size)
        .background(Color(white: 0.1))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(alignment: .topTrailing) {
            // Top right buttons: menu, add, and color picker stacked
            VStack(alignment: .trailing, spacing: size * 0.02) {
                HStack(spacing: size * 0.02) {
                    // Menu button (only when running/paused)
                    if timer.timerState == .running || timer.timerState == .paused {
                        Menu {
                            Button(action: { copyTimerAsMarkdown() }) {
                                Label("Copy as Markdown", systemImage: "doc.on.doc")
                            }
                            Divider()
                            Button(action: { timer.useAutoColor.toggle() }) {
                                Label("Auto Color", systemImage: timer.useAutoColor ? "checkmark.circle.fill" : "circle")
                            }
                            Button(action: { timer.useAutoClockface.toggle() }) {
                                Label("Auto Zoom", systemImage: timer.useAutoClockface ? "checkmark.circle.fill" : "circle")
                            }
                            Button(action: { timer.useFlashWarning.toggle() }) {
                                Label("Flash Warning", systemImage: timer.useFlashWarning ? "checkmark.circle.fill" : "circle")
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color(white: 0.2))
                                    .frame(width: size * 0.10, height: size * 0.10)
                                Image(systemName: "ellipsis")
                                    .font(.system(size: size * 0.04, weight: .medium))
                                    .foregroundStyle(.white)
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                    }

                    // Add button
                    if let onAdd = onAdd {
                        Button(action: onAdd) {
                            Image(systemName: "plus")
                                .font(.system(size: size * 0.04, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(width: size * 0.10, height: size * 0.10)
                                .background(Color(white: 0.2))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }

            }
            .padding(size * 0.03)
        }
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture {
            focusedField = nil
        }
        .onAppear {
            // Clear focus to prevent visible field highlight
            focusedField = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
    }

}

// MARK: - Time Digit Field (clickable number input)
struct TimeDigitField: View {
    @Binding var value: Int
    let maxValue: Int
    let isFocused: Bool
    var size: CGFloat = 110  // Field size for proportional scaling
    var onSubmit: (() -> Void)? = nil
    @State private var textValue: String = ""
    @State private var isEditing: Bool = false
    @State private var hasTyped: Bool = false
    @State private var showHighlight: Bool = false

    var body: some View {
        let fieldWidth: CGFloat = size
        let fieldHeight: CGFloat = size * 0.9
        let fontSize: CGFloat = size * 0.72

        ZStack {
            // Background - always present, orange when focused
            RoundedRectangle(cornerRadius: size * 0.07, style: .continuous)
                .fill(isFocused ? Color.green : Color.clear)
                .frame(width: fieldWidth, height: fieldHeight)

            TextField("", text: $textValue)
                .font(.system(size: fontSize, weight: .thin))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(width: fieldWidth, height: fieldHeight)
                .textFieldStyle(.plain)
                .tint(.clear)
                .focusEffectDisabled()
                .onSubmit {
                    onSubmit?()
                }
                .onAppear {
                    // Delay to prevent auto-focus on first field
                    DispatchQueue.main.async {
                        NSApp.keyWindow?.makeFirstResponder(nil)
                    }
                }
                .onChange(of: textValue) { oldValue, newValue in
                    // Filter to only digits
                    var filtered = newValue.filter { $0.isNumber }

                    // Detect if user is deleting (backspace) vs adding
                    let isDeleting = newValue.count < oldValue.count

                    // When user starts typing (not deleting) in focused field, replace old value
                    if isEditing && !hasTyped && !filtered.isEmpty && !isDeleting {
                        // User just started typing - use only the new digit(s)
                        let oldFormatted = String(format: "%02d", value)
                        if newValue.hasPrefix(oldFormatted) {
                            filtered = String(newValue.dropFirst(oldFormatted.count)).filter { $0.isNumber }
                        }
                        hasTyped = true
                    }

                    // If deleting, mark as typed so subsequent typing works normally
                    if isDeleting {
                        hasTyped = true
                    }

                    if filtered.count > 2 {
                        filtered = String(filtered.suffix(2))
                    }

                    // Update value (use 0 if empty)
                    if let num = Int(filtered), !filtered.isEmpty {
                        value = min(num, maxValue)
                    } else if filtered.isEmpty {
                        value = 0
                    }

                    // Always show with leading zero
                    let formatted = String(format: "%02d", value)
                    if textValue != formatted {
                        textValue = formatted
                    }
                }
                .onChange(of: value) { _, newValue in
                    if !isEditing {
                        textValue = String(format: "%02d", newValue)
                    }
                }
                .onChange(of: isFocused) { _, focused in
                    isEditing = focused
                    hasTyped = false
                    if !focused {
                        // Restore display when losing focus
                        textValue = String(format: "%02d", value)
                    }
                }
                .onAppear {
                    textValue = String(format: "%02d", value)
                }
        }
    }
}

// MARK: - Interactive Clock View (click to set time)
struct InteractiveClockView: View {
    @Binding var seconds: TimeInterval
    let maxSeconds: TimeInterval
    let isEditable: Bool

    var body: some View {
        ZStack {
            // Analog clock face display
            AnalogTimerView(
                remainingSeconds: seconds,
                clockfaceSeconds: maxSeconds
            )

            // NSDatePicker overlay when editable (invisible but functional)
            if isEditable {
                TimeDurationPicker(seconds: $seconds, maxSeconds: maxSeconds)
                    .frame(width: 150, height: 30)
                    .offset(y: 120) // Position below clock
            }
        }
    }
}

// MARK: - NSDatePicker Wrapper for Duration
struct TimeDurationPicker: NSViewRepresentable {
    @Binding var seconds: TimeInterval
    let maxSeconds: TimeInterval

    func makeNSView(context: Context) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerMode = .single
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = .hourMinuteSecond
        picker.font = NSFont.monospacedDigitSystemFont(ofSize: 20, weight: .regular)

        // Use reference date for duration
        let refDate = Date(timeIntervalSinceReferenceDate: 0)
        picker.minDate = refDate
        picker.maxDate = refDate.addingTimeInterval(maxSeconds)
        picker.dateValue = refDate.addingTimeInterval(seconds)

        picker.target = context.coordinator
        picker.action = #selector(Coordinator.dateChanged(_:))

        return picker
    }

    func updateNSView(_ picker: NSDatePicker, context: Context) {
        let refDate = Date(timeIntervalSinceReferenceDate: 0)
        picker.dateValue = refDate.addingTimeInterval(seconds)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject {
        var parent: TimeDurationPicker

        init(_ parent: TimeDurationPicker) {
            self.parent = parent
        }

        @objc func dateChanged(_ sender: NSDatePicker) {
            let refDate = Date(timeIntervalSinceReferenceDate: 0)
            parent.seconds = sender.dateValue.timeIntervalSince(refDate)
        }
    }
}

// MARK: - macOS Time Picker Column (replaces iOS wheel picker)
struct MacOSTimePickerColumn: View {
    @Binding var selection: Int
    let range: Range<Int>
    let label: String
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        HStack(spacing: 4) {
            // Picker area with drag support
            ZStack {
                // Selection highlight
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 40)

                // Numbers
                VStack(spacing: 0) {
                    ForEach(-2..<3, id: \.self) { offset in
                        let value = selection + offset
                        let isValid = range.contains(value)
                        Text(isValid ? "\(value)" : "")
                            .font(.system(size: offset == 0 ? 24 : 20, weight: offset == 0 ? .medium : .regular))
                            .foregroundColor(offset == 0 ? .white : .gray.opacity(0.5 - Double(abs(offset)) * 0.15))
                            .frame(height: 40)
                            .frame(maxWidth: .infinity)
                    }
                }
                .offset(y: dragOffset)
            }
            .frame(height: 200)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation.height * 0.3
                    }
                    .onEnded { value in
                        let change = -Int(round(value.translation.height / 40))
                        let newValue = max(range.lowerBound, min(range.upperBound - 1, selection + change))
                        withAnimation(.easeOut(duration: 0.2)) {
                            selection = newValue
                            dragOffset = 0
                        }
                    }
            )
            .frame(maxWidth: .infinity)

            Text(label)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 50, alignment: .leading)
        }
    }
}

// MARK: - Reusable Components

struct CircleButton: View {
    let title: String
    let textColor: Color
    let backgroundColor: Color
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 80, height: 80)

                Circle()
                    .stroke(backgroundColor, lineWidth: 0)
                    .frame(width: 86, height: 86)

                Text(title)
                    .foregroundStyle(disabled ? .gray : textColor)
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }
}

// MARK: - Analog Timer View (configurable clock face)
struct AnalogTimerView: View {
    var remainingSeconds: Double
    var clockfaceSeconds: Double  // Clock face scale in seconds
    var pieColor: Color = .orange  // Color of the pie slice
    var onSetTime: ((Double) -> Void)? = nil  // Callback when user clicks to set time

    private var clockMaxSeconds: Double {
        clockfaceSeconds
    }

    private var clockLabels: [Int] {
        let mins = Int(clockfaceSeconds / 60)
        let hours = Int(clockfaceSeconds / 3600)

        // Aim for ~12 labels with sensible divisors
        switch hours {
        case 96: return stride(from: 0, to: 96, by: 8).map { $0 }     // 12 labels
        case 72: return stride(from: 0, to: 72, by: 6).map { $0 }     // 12 labels
        case 48: return stride(from: 0, to: 48, by: 4).map { $0 }     // 12 labels
        case 24: return stride(from: 0, to: 24, by: 2).map { $0 }     // 12 labels
        case 16: return stride(from: 0, to: 16, by: 2).map { $0 }     // 8 labels
        case 12: return stride(from: 0, to: 12, by: 1).map { $0 }     // 12 labels (standard clock)
        case 8: return stride(from: 0, to: 8, by: 1).map { $0 }       // 8 labels
        case 4: return stride(from: 0, to: 4, by: 1).map { $0 }       // 4 labels
        default: break
        }

        // For scales <= 60 seconds or <= 60 minutes, use standard 60-unit clock face
        let secs = Int(clockfaceSeconds)
        if secs <= 60 {
            // Use 60-second clock face for all sub-minute scales (15s, 30s, 45s, 60s)
            return stride(from: 0, to: 60, by: 5).map { $0 }  // 0, 5, 10, 15...55
        }

        switch mins {
        case 120: return stride(from: 0, to: 120, by: 10).map { $0 }  // 12 labels
        case 90: return stride(from: 0, to: 90, by: 15).map { $0 }    // 0, 15, 30, 45, 60, 75 (6 labels)
        case 60: return stride(from: 0, to: 60, by: 5).map { $0 }     // 12 labels
        case 30: return stride(from: 0, to: 30, by: 5).map { $0 }     // 0, 5, 10, 15, 20, 25 (6 labels)
        case 15: return stride(from: 0, to: 15, by: 3).map { $0 }     // 0, 3, 6, 9, 12 (5 labels)
        case 9: return stride(from: 0, to: 9, by: 1).map { $0 }       // 0-8 (9 labels)
        case 5: return stride(from: 0, to: 5, by: 1).map { $0 }       // 0-4 (5 labels)
        default:
            let step = max(mins / 12, 1)
            return stride(from: 0, to: mins, by: step).map { $0 }
        }
    }

    private var isHourScale: Bool {
        clockfaceSeconds >= 3600 && clockfaceSeconds > 7200  // More than 2 hours = hour labels
    }

    private var tickCount: Int {
        60  // Always 60 ticks like a clock
    }

    private var maxValue: Int {
        let secs = Int(clockfaceSeconds)
        let mins = Int(clockfaceSeconds / 60)
        let hours = clockfaceSeconds / 3600

        // For hour scales > 2h, use hours
        if hours > 2 { return Int(hours) }
        // For sub-minute scales, use 60 seconds
        if secs <= 60 { return 60 }
        // For specific minute scales, use actual minutes
        if mins == 5 || mins == 9 || mins == 15 || mins == 30 || mins == 90 { return mins }
        // For 60 mins, use 60
        if mins <= 60 { return 60 }
        // For 120 mins
        return mins
    }

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let degreesPerTick = 360.0 / Double(tickCount)

            ZStack {
                // Background circle (white) - smaller to leave room for labels outside
                Circle()
                    .fill(Color.white)
                    .frame(width: size * 0.65, height: size * 0.65)

                // Tick marks - aligned with labels (drawn before red so they're underneath)
                let labelAngles = clockLabels.map { value -> Double in
                    Double(value) / Double(maxValue) * 360.0
                }
                let minorTicksPerSegment = 4

                ForEach(0..<labelAngles.count, id: \.self) { i in
                    let majorAngle = labelAngles[i]
                    let nextAngle = i < labelAngles.count - 1 ? labelAngles[i + 1] : 360.0
                    let segmentSize = nextAngle - majorAngle

                    // Major tick at label position (on clock edge)
                    Rectangle()
                        .fill(Color.black.opacity(0.7))
                        .frame(width: size * 0.015, height: size * 0.06)
                        .offset(y: -(size * 0.29))
                        .rotationEffect(.degrees(majorAngle))

                    // Minor ticks between labels
                    ForEach(1...minorTicksPerSegment, id: \.self) { j in
                        let minorAngle = majorAngle + (segmentSize * Double(j) / Double(minorTicksPerSegment + 1))
                        Rectangle()
                            .fill(Color.black.opacity(0.7))
                            .frame(width: size * 0.008, height: size * 0.03)
                            .offset(y: -(size * 0.30))
                            .rotationEffect(.degrees(minorAngle))
                    }
                }

                // Pie (remaining time) - shrinks CW from 12 o'clock (on top of ticks)
                if remainingSeconds > 0 {
                    let angle = (remainingSeconds / clockMaxSeconds) * 360
                    PieSlice(
                        startAngle: .degrees(-90),
                        endAngle: .degrees(-90 - angle),
                        clockwise: true
                    )
                    .fill(pieColor)
                    .frame(width: size * 0.65, height: size * 0.65)
                }

                // Number labels (CCW from top) - outside the clock
                ForEach(clockLabels, id: \.self) { value in
                    let position = Double(value) / Double(maxValue)
                    let angle = -position * 360.0 - 90  // CCW
                    let radius = size * 0.42  // Outside the clock edge
                    let x = radius * cos(angle * .pi / 180)
                    let y = radius * sin(angle * .pi / 180)
                    Text("\(value)")
                        .font(.system(size: size * 0.08, weight: .bold))
                        .foregroundColor(.white)
                        .position(x: size/2 + x, y: size/2 + y)
                }

                // Center dot
                Circle()
                    .fill(Color.black)
                    .frame(width: size * 0.04, height: size * 0.04)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard let onSetTime = onSetTime else { return }
                        let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                        let dx = value.location.x - center.x
                        let dy = value.location.y - center.y

                        // Calculate angle from 12 o'clock (CCW = positive time)
                        var angle = atan2(dx, -dy) * 180 / .pi  // 0° at top, CW positive
                        if angle < 0 { angle += 360 }

                        // Convert angle to seconds (CCW direction)
                        let fraction = (360 - angle) / 360
                        let seconds = fraction * clockfaceSeconds
                        onSetTime(max(0, seconds))
                    }
            )
        }
    }
}

struct PieSlice: Shape {
    var startAngle: Angle
    var endAngle: Angle
    var clockwise: Bool = false

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2

        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: clockwise
        )
        path.closeSubpath()

        return path
    }
}

#Preview {
    ContentView()
}
