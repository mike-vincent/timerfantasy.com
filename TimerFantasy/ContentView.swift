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
}

// MARK: - Timer Store (iCloud + UserDefaults persistence)
class TimerStore: ObservableObject {
    static let shared = TimerStore()
    private let iCloudKey = "com.michaelvincent.TimerFantasy.timers"
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
                initialSetSeconds: timer.initialSetSeconds
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
            timerState = .alarming
            playAlarmSound()
        } else {
            timeRemaining = remaining
        }
    }

    func playAlarmSound() {
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
    case hours96, hours72, hours48, hours24, minutes120, minutes60, minutes15, minutes5

    var seconds: Double {
        switch self {
        case .hours96: return 96 * 3600
        case .hours72: return 72 * 3600
        case .hours48: return 48 * 3600
        case .hours24: return 24 * 3600
        case .minutes120: return 120 * 60
        case .minutes60: return 60 * 60
        case .minutes15: return 15 * 60
        case .minutes5: return 5 * 60
        }
    }

    var label: String {
        switch self {
        case .hours96: return "96h"
        case .hours72: return "72h"
        case .hours48: return "48h"
        case .hours24: return "24h"
        case .minutes120: return "120m"
        case .minutes60: return "60m"
        case .minutes15: return "15m"
        case .minutes5: return "5m"
        }
    }
}

// MARK: - Main View
struct ContentView: View {
    @State private var timers: [TimerModel] = []
    @State private var saveTimer: AnyCancellable?
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
                                TimerCardView(timer: timers[index], compact: true, size: cardSize, onDelete: timers.count > 1 ? {
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
        "Glass (Default)", "Basso", "Blow", "Bottle", "Frog", "Funk",
        "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"
    ]

    var availableClockfaces: [ClockfaceScale] {
        // Only allow clockfaces that fit the initial set time (not larger)
        ClockfaceScale.allCases.filter { $0.seconds >= timer.initialSetSeconds }
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
        case .running, .alarming: return .orange
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
                        TimeDigitField(value: $timer.selectedMinutes, maxValue: 59, isFocused: focusedField == .minutes, size: size * 0.22, onSubmit: { timer.start() })
                            .focused($focusedField, equals: .minutes)
                        Text(":")
                            .font(.system(size: digitFontSize, weight: .thin))
                            .foregroundStyle(.white)
                            .frame(width: size * 0.05)
                            .transition(.opacity.combined(with: .scale))
                        TimeDigitField(value: $timer.selectedSeconds, maxValue: 59, isFocused: focusedField == .seconds, size: size * 0.22, onSubmit: { timer.start() })
                            .focused($focusedField, equals: .seconds)
                    }

                    // Duration and Sound pickers - stacked vertically
                    VStack(spacing: size * 0.01) {
                        // Duration picker (1-60 seconds)
                        Menu {
                            ForEach(1...60, id: \.self) { seconds in
                                Button(seconds == 5 ? "5s (Default)" : "\(seconds)s") {
                                    timer.alarmDuration = seconds
                                }
                            }
                        } label: {
                            Text(timer.alarmDuration == 5 ? "5s (Default)" : "\(timer.alarmDuration)s")
                                .font(.system(size: buttonFontSize, weight: .medium))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .menuStyle(.borderlessButton)

                        // Sound picker
                        Menu {
                            ForEach(alarmSounds, id: \.self) { sound in
                                Button(sound) {
                                    timer.selectedAlarmSound = sound
                                    // Preview sound
                                    let soundName = sound.replacingOccurrences(of: " (Default)", with: "")
                                    if let s = NSSound(named: NSSound.Name(soundName)) {
                                        s.play()
                                    }
                                }
                            }
                        } label: {
                            Text(timer.selectedAlarmSound)
                                .font(.system(size: buttonFontSize, weight: .medium))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .menuStyle(.borderlessButton)
                    }
                } else if timer.timerState == .alarming {
                    // Alarming: show bell with end time below, tap to dismiss
                    VStack(spacing: size * 0.02) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: size * 0.3))
                            .foregroundStyle(.orange)
                            .symbolEffect(.pulse, options: .repeating, isActive: timer.isAlarmRinging)

                        // End time hung below bell
                        HStack(spacing: size * 0.01) {
                            Image(systemName: "bell.fill")
                                .font(.system(size: size * 0.025))
                            Text(getEndTimeString())
                                .font(.system(size: size * 0.035, weight: .medium))
                        }
                        .foregroundStyle(.white.opacity(0.5))
                    }
                    .onTapGesture {
                        timer.dismissAlarm()
                    }
                } else {
                    // Running/Paused: show clock and countdown
                    ZStack {
                        AnalogTimerView(
                            remainingSeconds: timer.timeRemaining,
                            clockfaceSeconds: timer.selectedClockface.seconds,
                            onSetTime: { seconds in
                                timer.timeRemaining = max(1, seconds)
                                timer.endTime = Date().addingTimeInterval(seconds)
                            }
                        )

                        // Initial set time - below center dot
                        Text(timer.initialTimeFormatted)
                            .font(.system(size: clockSize * 0.07, weight: .medium))
                            .foregroundStyle(.black.opacity(0.5))
                            .offset(y: clockSize * 0.08)
                    }
                    .frame(width: clockSize, height: clockSize)

                    // End time with bell icon (below circle, above countdown)
                    HStack(spacing: size * 0.01) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: size * 0.025))
                        Text(getEndTimeString())
                            .font(.system(size: size * 0.035, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.5))

                    Text(formatDuration(timer.timeRemaining))
                        .font(.system(size: countdownFontSize, weight: .thin))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
            }

            // Top row: clockface toggle (left) - only when running/paused
            if timer.timerState == .running || timer.timerState == .paused {
                VStack {
                    HStack {
                        // Clockface toggle - top left
                        Button(action: cycleClockface) {
                            Text("\(timer.selectedClockface.label) Watchface")
                                .font(.system(size: size * 0.035, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, size * 0.04)
                                .padding(.vertical, size * 0.02)
                                .background(Color.gray.opacity(0.3))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
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
                                .foregroundStyle(timer.timerState == .idle && onDelete == nil ? .gray : .white)
                                .frame(width: buttonWidth, height: buttonHeight)
                                .background(Color(white: 0.2))
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
                    Button("Delete", role: .destructive) {
                        onDelete?()
                    }
                    .keyboardShortcut(.defaultAction)
                    Button("Keep", role: .cancel) {}
                }
                .confirmationDialog("Cancel Timer?", isPresented: $showCancelConfirmation) {
                    Button("Cancel Timer", role: .destructive) {
                        timer.cancel()
                    }
                    .keyboardShortcut(.defaultAction)
                    Button("Keep Running", role: .cancel) {}
                }
            }
        }
        .frame(width: size, height: size)
        .background(Color(white: 0.1))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(alignment: .topTrailing) {
            // Glass + button top right of each card
            if let onAdd = onAdd {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: size * 0.06, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: size * 0.12, height: size * 0.12)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(size * 0.03)
            }
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
                .fill(isFocused ? Color.orange : Color.clear)
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
        default: break
        }

        switch mins {
        case 120: return stride(from: 0, to: 120, by: 10).map { $0 }  // 12 labels
        case 60: return stride(from: 0, to: 60, by: 5).map { $0 }     // 12 labels
        case 15: return stride(from: 0, to: 15, by: 5).map { $0 }     // 3 labels: 0,5,10
        case 5: return [0, 1, 2, 3, 4]                                 // 5 labels
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
        let mins = Int(clockfaceSeconds / 60)
        let hours = clockfaceSeconds / 3600

        // For hour scales > 2h, use hours; otherwise use minutes
        if hours > 2 { return Int(hours) }
        else { return mins }
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

                // Red pie (remaining time) - shrinks CW from 12 o'clock (on top of ticks)
                if remainingSeconds > 0 {
                    let angle = (remainingSeconds / clockMaxSeconds) * 360
                    PieSlice(
                        startAngle: .degrees(-90),
                        endAngle: .degrees(-90 - angle),
                        clockwise: true
                    )
                    .fill(Color.orange)
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
