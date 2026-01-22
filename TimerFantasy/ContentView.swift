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
    var startTime: Date?
    var timerLabel: String
    var selectedAlarmSound: String
    var alarmDuration: Int
    var selectedClockface: String
    var initialSetSeconds: TimeInterval
    var isLooping: Bool
    var timerColorHex: String?  // Hex string for pie slice color
    var useAutoColor: Bool?
    var useAutoClockface: Bool?
    // End At mode settings
    var useEndAtMode: Bool?
    var endAtHour: Int?
    var endAtMinute: Int?
    var endAtIsPM: Bool?
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
                startTime: timer.startTime,
                timerLabel: timer.timerLabel,
                selectedAlarmSound: timer.selectedAlarmSound,
                alarmDuration: timer.alarmDuration,
                selectedClockface: timer.selectedClockface.rawValue,
                initialSetSeconds: timer.initialSetSeconds,
                isLooping: timer.isLooping,
                timerColorHex: timer.timerColor.hexString,
                useAutoColor: timer.useAutoColor,
                useAutoClockface: timer.useAutoClockface,
                useEndAtMode: timer.useEndAtMode,
                endAtHour: timer.endAtHour,
                endAtMinute: timer.endAtMinute,
                endAtIsPM: timer.endAtIsPM
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
            if let useEndAtMode = data.useEndAtMode {
                timer.useEndAtMode = useEndAtMode
            }
            if let endAtHour = data.endAtHour {
                timer.endAtHour = endAtHour
            }
            if let endAtMinute = data.endAtMinute {
                timer.endAtMinute = endAtMinute
            }
            if let endAtIsPM = data.endAtIsPM {
                timer.endAtIsPM = endAtIsPM
            }

            // Restore running timer based on endTime
            if timer.timerState == .running, let endTime = data.endTime {
                let remaining = endTime.timeIntervalSinceNow
                if remaining > 0 {
                    timer.timeRemaining = remaining
                    timer.endTime = endTime
                    // Use stored startTime, or calculate if missing (migration)
                    timer.startTime = data.startTime ?? endTime.addingTimeInterval(-timer.initialSetSeconds)
                } else {
                    // Timer expired while app was closed
                    timer.timerState = .idle
                    timer.timeRemaining = 0
                    timer.endTime = nil
                    timer.startTime = nil
                }
            } else if timer.timerState == .paused {
                timer.timeRemaining = data.timeRemaining
                timer.endTime = nil
                // For paused, calculate startTime if missing
                timer.startTime = data.startTime ?? Date().addingTimeInterval(-timer.initialSetSeconds + data.timeRemaining)
            } else if timer.timerState == .alarming {
                // Preserve endTime for alarming state (shows when alarm went off)
                timer.endTime = data.endTime
                timer.startTime = data.startTime ?? data.endTime?.addingTimeInterval(-timer.initialSetSeconds)
                timer.timeRemaining = 0
            } else {
                timer.timeRemaining = 0
                timer.endTime = nil
                timer.startTime = nil
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
    @Published var startTime: Date?
    @Published var timerLabel: String = "Timer"
    @Published var selectedAlarmSound: String = "Glass (Default)"
    @Published var alarmDuration: Int = 5  // seconds (1-60)
    @Published var selectedClockface: ClockfaceScale = .minutes60
    @Published var initialSetSeconds: TimeInterval = 0  // Time originally set when started
    @Published var isAlarmRinging: Bool = false  // True while sound is playing
    @Published var isLooping: Bool = false  // Auto-restart when timer ends
    @Published var timerColor: Color = .orange  // Pie slice color (manual)
    @Published var useAutoColor: Bool = false  // false = orange (default), true = red
    @Published var useAutoClockface: Bool = true  // Auto-shrink watchface as time decreases
    // End At mode settings
    @Published var useEndAtMode: Bool = false
    @Published var endAtHour: Int = 12
    @Published var endAtMinute: Int = 0
    @Published var endAtIsPM: Bool = false

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

    // Compact format for default timer name: "55h32m Timer", "22m Timer", "33s Timer"
    var defaultTimerName: String {
        let total = Int(initialSetSeconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return "\(h)h\(m)m Timer"  // Hours + minutes
        } else if m > 0 {
            return "\(m)m Timer"  // Minutes only
        } else {
            return "\(s)s Timer"  // Seconds only
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

    // Effective color (auto or manual)
    var effectiveColor: Color {
        useAutoColor ? autoColor : timerColor
    }

    // Translucent ruby red like litho tape
    var autoColor: Color {
        .red.opacity(0.85)
    }

    func start() {
        guard totalSetSeconds > 0 else { return }
        initialSetSeconds = totalSetSeconds
        timeRemaining = totalSetSeconds
        startTime = Date()
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
        isAlarmRinging = true

        // Skip sound if No Sound selected, but still throb for alarmDuration
        if selectedAlarmSound == "No Sound" {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(alarmDuration)) { [weak self] in
                self?.isAlarmRinging = false
            }
            return
        }

        // Extract sound name without "(Default)" suffix
        let soundName = selectedAlarmSound.replacingOccurrences(of: " (Default)", with: "")

        // Try to play from system sounds, loop for alarmDuration seconds
        if let sound = NSSound(named: NSSound.Name(soundName)) {
            currentSound = sound
            sound.loops = true
            sound.play()

            // Stop sound after alarmDuration seconds
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
    case hours96, hours48, hours16, hours12, hours4, minutes120, minutes90, minutes60, minutes30, minutes15, minutes9, minutes5, seconds60

    var seconds: Double {
        switch self {
        case .hours96: return 96 * 3600
        case .hours48: return 48 * 3600
        case .hours16: return 16 * 3600
        case .hours12: return 12 * 3600
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
        case .hours48: return "48h"
        case .hours16: return "16h"
        case .hours12: return "12h"
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

// MARK: - Vertical Alignment
enum VerticalAlignment: String, CaseIterable {
    case top, middle, bottom

    var next: VerticalAlignment {
        switch self {
        case .top: return .middle
        case .middle: return .bottom
        case .bottom: return .top
        }
    }

    var frameAlignment: Alignment {
        switch self {
        case .top: return .top
        case .middle: return .center
        case .bottom: return .bottom
        }
    }

    var icon: String {
        switch self {
        case .top: return "arrow.up.to.line"
        case .middle: return "arrow.up.and.down"
        case .bottom: return "arrow.down.to.line"
        }
    }
}

// MARK: - Main View
struct ContentView: View {
    @State private var timers: [TimerModel] = []
    @State private var saveTimer: AnyCancellable?
    @State private var draggingTimer: TimerModel?
    @State private var saveCounter: Int = 0
    @AppStorage("verticalAlignment") private var verticalAlignment: String = "middle"
    let globalTimer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    private let spacing: CGFloat = 8
    private let columnCount = 2
    private let baseCardSize: CGFloat = 200

    private var currentAlignment: VerticalAlignment {
        VerticalAlignment(rawValue: verticalAlignment) ?? .middle
    }

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

        // Square cards (1:1 aspect ratio)
        let cardAspect = 1.0  // width / height
        for testCols in 1...itemCount {
            let testRows = Int(ceil(Double(itemCount) / Double(testCols)))
            let gridRatio = (Double(testCols) * cardAspect) / Double(testRows)
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
        // Minimum size for one square card
        window.minSize = NSSize(width: baseCardSize + spacing * 2, height: baseCardSize + spacing * 2 + 28)
    }

    var body: some View {
        GeometryReader { geo in
            let allItems = max(1, timers.count)
            let windowRatio = geo.size.width / geo.size.height
            let layout = bestGridLayout(itemCount: allItems, windowRatio: windowRatio)
            let actualCols = layout.cols
            let actualRows = layout.rows

            // Card size to fill available space based on actual grid dimensions (square)
            let availableWidth = geo.size.width - spacing * CGFloat(actualCols + 1)
            let availableHeight = geo.size.height - spacing * CGFloat(actualRows + 1)
            let maxCardWidth = availableWidth / CGFloat(actualCols)
            let maxCardHeight = availableHeight / CGFloat(actualRows)
            let cardSize = min(maxCardWidth, maxCardHeight)

            let actualGridWidth = CGFloat(actualCols) * cardSize + CGFloat(actualCols - 1) * spacing
            let actualGridHeight = CGFloat(actualRows) * cardSize + CGFloat(actualRows - 1) * spacing

            VStack(spacing: spacing) {
                ForEach(0..<actualRows, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(0..<actualCols, id: \.self) { col in
                            let index = row * actualCols + col
                            if index < timers.count {
                                let timer = timers[index]
                                TimerCardView(timer: timer, compact: true, size: cardSize, onDelete: {
                                    _ = withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        timers.remove(at: index)
                                    }
                                    saveTimers()
                                }, onAdd: {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: currentAlignment.frameAlignment)
            .padding(spacing)
            .overlay(alignment: .topTrailing) {
                let overlayButtonSize = cardSize * 0.12
                let overlayFontSize = cardSize * 0.05
                if timers.isEmpty {
                    Button(action: {
                        timers.append(TimerModel())
                        TimerStore.shared.save(timers)
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: overlayFontSize, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: overlayButtonSize, height: overlayButtonSize)
                            .background(Circle().fill(Color(white: 0.2)))
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                } else {
                    Button(action: {
                        verticalAlignment = currentAlignment.next.rawValue
                    }) {
                        Image(systemName: currentAlignment.icon)
                            .font(.system(size: overlayFontSize, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: overlayButtonSize, height: overlayButtonSize)
                            .background(Circle().fill(Color(white: 0.2)))
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // Load saved timers
            timers = TimerStore.shared.load()
            setupWindow()
        }
        .onReceive(globalTimer) { _ in
            for timer in timers {
                timer.update()
            }
            // Save once per second (every 20 ticks at 0.05s interval)
            saveCounter += 1
            if saveCounter >= 20 {
                saveCounter = 0
                saveTimers()
            }
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
    var onSave: (() -> Void)? = nil

    // Debug flag to show row borders
    private let showDebugBorders = false

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
            timer.selectedClockface = available.last ?? .hours12
        }
    }

    @FocusState private var focusedField: TimeField?
    @State private var showDeleteConfirmation = false
    @State private var showCancelConfirmation = false
    @State private var showOptionsMenu = false
    @State private var labelBeforeEdit: String = ""
    @State private var showEndAtPicker = false
    @State private var selectedEndTime = Date()
    @State private var isEditingLabel = false
    @State private var selectedPreset: String? = nil
    @State private var blinkOn: Bool = true
    @State private var currentTime: Date = Date()
    @State private var idleMode: IdleMode = .countdown
    @State private var clockDisplayMode: ClockDisplayMode = .digital

    enum IdleMode {
        case endAt
        case clock
        case countdown
    }

    enum ClockDisplayMode {
        case digital
        case analog
    }

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
        case .running: return .green
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

    private func dismissAlarmToClock() {
        idleMode = .clock
        timer.dismissAlarm()
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

    func formatDurationWords(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h) hr") }
        if m > 0 { parts.append("\(m) min") }
        if s > 0 { parts.append("\(s) sec") }
        if parts.isEmpty { parts.append("0 sec") }
        return parts.joined(separator: " ")
    }

    func getEndTimeString() -> String {
        guard let end = timer.endTime else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: end)
    }

    func getStartTimeString() -> String {
        guard let start = timer.startTime else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: start)
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

    func updateEndAtDuration() {
        // Convert 12-hour to 24-hour
        var hour24 = timer.endAtHour
        if timer.endAtHour == 12 {
            hour24 = timer.endAtIsPM ? 12 : 0
        } else {
            hour24 = timer.endAtIsPM ? timer.endAtHour + 12 : timer.endAtHour
        }

        // Create target date
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour24
        components.minute = timer.endAtMinute
        components.second = 0

        guard var targetDate = calendar.date(from: components) else { return }

        // If target is in the past, assume tomorrow
        if targetDate <= Date() {
            targetDate = calendar.date(byAdding: .day, value: 1, to: targetDate) ?? targetDate
        }

        let duration = targetDate.timeIntervalSinceNow
        if duration > 0 {
            let total = Int(duration)
            timer.selectedHours = total / 3600
            timer.selectedMinutes = (total % 3600) / 60
            timer.selectedSeconds = total % 60
        }
    }

    // MARK: - Extracted View Builders

    @ViewBuilder
    private func idleStateView(padding: CGFloat, digitFontSize: CGFloat) -> some View {
        let toolbarHeight = size / 6  // Same as countdown/alarming
        let middleHeight = size - (toolbarHeight * 2)  // Middle section
        let shortRowHeight = middleHeight * 0.25  // Rows 2 & 4: toggle and presets
        let inputRowHeight = middleHeight * 0.5  // Row 3: time input / clock
        let labelMaxWidth = size - (padding * 2) - (size * 0.12 * 4)

        // Row 1: Top row - trash, placeholder, label, gear, +
        HStack {
            Button(action: { showDeleteConfirmation = true }) {
                Image(systemName: "xmark")
                    .font(.system(size: size * 0.05, weight: .medium))
                    .foregroundStyle(onDelete == nil ? .gray : .white)
                    .frame(width: size * 0.12, height: size * 0.12)
                    .background(Color(white: 0.2))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(onDelete == nil)

            // Placeholder to balance gear button on right
            Color.clear.frame(width: size * 0.12, height: size * 0.12)

            Spacer()

            Text(timer.timerLabel.isEmpty || timer.timerLabel == "Timer" ? "Timer" : timer.timerLabel)
                .font(.system(size: size * 0.06, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .allowsTightening(true)
                .multilineTextAlignment(.center)
                .frame(maxWidth: labelMaxWidth)
                .onTapGesture {
                    isEditingLabel = true
                }
                .popover(isPresented: $isEditingLabel) {
                    TextField("Timer", text: $timer.timerLabel)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                        .padding()
                }

            Spacer()

            // Settings menu for sound/loop options
            Button(action: { showOptionsMenu = true }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: size * 0.05, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: size * 0.12, height: size * 0.12)
                    .background(Color(white: 0.2))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showOptionsMenu) {
                idleOptionsMenuContent
            }

            // Add button or placeholder
            if let onAdd = onAdd {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: size * 0.05, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: size * 0.12, height: size * 0.12)
                        .background(Color(white: 0.2))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: size * 0.12, height: size * 0.12)
            }
        }
        .padding(.horizontal, padding)
        .frame(width: size)
        .frame(height: toolbarHeight)
        .border(showDebugBorders ? Color.red : Color.clear)

        // Row 2: End At | Countdown toggle (two equal-width capsules)
        // Calculate capsule height to match preset circle size
        let presetSpacing = size * 0.015
        let presetAvailableWidth = size - (padding * 2) - (presetSpacing * 6)
        let capsuleHeight = min(presetAvailableWidth / 7, shortRowHeight * 0.65)

        HStack(spacing: size * 0.02) {
            Button(action: {
                idleMode = .endAt
                timer.useEndAtMode = true
            }) {
                HStack(spacing: size * 0.015) {
                    Text("End At")
                }
                .font(.system(size: capsuleHeight * 0.45, weight: .medium))
                .foregroundStyle(idleMode == .endAt ? .black : .white.opacity(0.7))
                .frame(maxWidth: .infinity)
                .frame(height: capsuleHeight)
                .background(Capsule().fill(idleMode == .endAt ? Color.white : Color(white: 0.2)))
            }
            .buttonStyle(.plain)

            Button(action: {
                if idleMode == .clock {
                    clockDisplayMode = (clockDisplayMode == .digital) ? .analog : .digital
                } else {
                    idleMode = .clock
                }
            }) {
                HStack(spacing: size * 0.015) {
                    Text("Clock")
                }
                .font(.system(size: capsuleHeight * 0.45, weight: .medium))
                .foregroundStyle(idleMode == .clock ? .black : .white.opacity(0.7))
                .frame(maxWidth: .infinity)
                .frame(height: capsuleHeight)
                .background(Capsule().fill(idleMode == .clock ? Color.white : Color(white: 0.2)))
            }
            .buttonStyle(.plain)

            Button(action: {
                idleMode = .countdown
                timer.useEndAtMode = false
            }) {
                HStack(spacing: size * 0.015) {
                    Text("Countdown")
                }
                .font(.system(size: capsuleHeight * 0.45, weight: .medium))
                .foregroundStyle(idleMode == .countdown ? .black : .white.opacity(0.7))
                .frame(maxWidth: .infinity)
                .frame(height: capsuleHeight)
                .background(Capsule().fill(idleMode == .countdown ? Color.white : Color(white: 0.2)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, padding)
        .frame(width: size)
        .frame(height: shortRowHeight)
        .border(showDebugBorders ? Color.green : Color.clear)

        // Row 3: Time input / clock (taller, vertically centered)
        if idleMode == .clock {
            if clockDisplayMode == .digital {
                CurrentTimeSlotsView(date: currentTime, cardSize: size)
                    .frame(width: size, height: inputRowHeight, alignment: .center)
                    .border(showDebugBorders ? Color.gray : Color.clear)
            } else {
                CurrentTimeClockFaceView(date: currentTime)
                    .frame(width: inputRowHeight * 0.95, height: inputRowHeight * 0.95)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .border(showDebugBorders ? Color.gray : Color.clear)
            }
        } else if idleMode == .endAt {
            endAtInputView(rowHeight: inputRowHeight)
                .frame(width: size, height: inputRowHeight, alignment: .center)
                .border(showDebugBorders ? Color.cyan : Color.clear)
        } else {
            countdownInputView(rowHeight: inputRowHeight)
                .frame(width: size, height: inputRowHeight, alignment: .center)
                .border(showDebugBorders ? Color.cyan : Color.clear)
        }

        // Row 4: Presets
        presetsRow(padding: padding, rowHeight: shortRowHeight)
            .frame(width: size)
            .frame(height: shortRowHeight)
            .border(showDebugBorders ? Color.blue : Color.clear)

        // Row 5: Start button
        startButton(padding: padding, rowHeight: toolbarHeight)
            .frame(width: size)
            .frame(height: toolbarHeight)
            .border(showDebugBorders ? Color.purple : Color.clear)
    }

    @ViewBuilder
    private func presetsRow(padding: CGFloat, rowHeight: CGFloat) -> some View {
        let segmentedPresets = ["5", "10", "15", "20", "30", "45", "60"]
        let availableWidth = size - (padding * 2)
        let separatorWidth: CGFloat = 1
        let segmentWidth = (availableWidth - (separatorWidth * CGFloat(segmentedPresets.count - 1))) / CGFloat(segmentedPresets.count)

        segmentedPresetControl(presets: segmentedPresets, rowHeight: rowHeight, segmentWidth: segmentWidth)
            .frame(width: availableWidth)
            .padding(.horizontal, padding)
    }

    @ViewBuilder
    private func segmentedPresetControl(presets: [String], rowHeight: CGFloat, segmentWidth: CGFloat) -> some View {
        let segmentHeight = rowHeight * 0.7
        let fontSize = segmentHeight * 0.35
        let cornerRadius = segmentHeight / 2

        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(white: 0.2))

            HStack(spacing: 0) {
                ForEach(Array(presets.enumerated()), id: \.offset) { index, preset in
                    let isSelected = selectedPreset == preset
                    Button(action: { applyPreset(preset) }) {
                        ZStack {
                            if isSelected {
                                Color.white
                            } else {
                                Color.clear
                            }
                            Text("\(preset)m")
                                .font(.system(size: fontSize, weight: .medium))
                                .minimumScaleFactor(0.5)
                                .lineLimit(1)
                                .foregroundStyle(isSelected ? .black : .white.opacity(0.7))
                        }
                        .frame(width: segmentWidth, height: segmentHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index != presets.count - 1 {
                        Rectangle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 1, height: segmentHeight * 0.7)
                    }
                }
            }
        }
        .frame(width: (segmentWidth * CGFloat(presets.count)) + CGFloat(presets.count - 1), height: segmentHeight)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private func compactPresetButton(preset: String, rowHeight: CGFloat, capsuleWidth: CGFloat) -> some View {
        let isSelected = selectedPreset == preset
        let capsuleHeight = rowHeight * 0.7
        let fontSize = capsuleHeight * 0.35
        Button(action: { applyPreset(preset) }) {
            Text("\(preset)m")
                .font(.system(size: fontSize, weight: .medium))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(isSelected ? .black : .white.opacity(0.7))
                .frame(width: capsuleWidth, height: capsuleHeight)
                .background(Capsule().fill(isSelected ? Color.white : Color(white: 0.2)))
        }
        .buttonStyle(.plain)
    }

    private func applyPreset(_ preset: String) {
        selectedPreset = preset
        let minutes = Int(preset) ?? 0
        if idleMode == .endAt {
            // Set end time to current time + preset minutes
            let endDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
            let calendar = Calendar.current
            var hour = calendar.component(.hour, from: endDate)
            let minute = calendar.component(.minute, from: endDate)
            let isPM = hour >= 12
            if hour > 12 { hour -= 12 }
            if hour == 0 { hour = 12 }
            timer.endAtHour = hour
            timer.endAtMinute = minute
            timer.endAtIsPM = isPM
        } else {
            // Set countdown duration
            timer.selectedHours = minutes / 60
            timer.selectedMinutes = minutes % 60
            timer.selectedSeconds = 0
        }
    }


    @ViewBuilder
    private func endAtInputView(rowHeight: CGFloat) -> some View {
        // Use smaller fields so HH:MM + AM/PM fits (same font size as countdown)
        let availableWidth = size * 0.9
        let colonWidth = size * 0.04
        // Fit 3 fields + 2 colons worth of space (same as countdown), but we use 3 fields + 1 colon
        let fieldSize = (availableWidth - (colonWidth * 2)) / 3
        HStack(spacing: 0) {
            TimeDigitField(value: $timer.endAtHour, maxValue: 12, isFocused: focusedField == .hours, size: fieldSize, onSubmit: { timer.start() })
                .focused($focusedField, equals: .hours)
            Text(":")
                .font(.system(size: fieldSize * 0.65, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: colonWidth)
            TimeDigitField(value: $timer.endAtMinute, maxValue: 59, isFocused: focusedField == .minutes, size: fieldSize, onSubmit: { timer.start() })
                .focused($focusedField, equals: .minutes)
            Button(action: { timer.endAtIsPM.toggle() }) {
                Text(timer.endAtIsPM ? "PM" : "AM")
                    .font(.system(size: fieldSize * 0.72, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: fieldSize + colonWidth, height: fieldSize * 0.9)  // Extra colon width for AM/PM
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: timer.endAtHour) { _, _ in updateEndAtDuration() }
        .onChange(of: timer.endAtMinute) { _, _ in updateEndAtDuration() }
        .onChange(of: timer.endAtIsPM) { _, _ in updateEndAtDuration() }
    }

    @ViewBuilder
    private func countdownInputView(rowHeight: CGFloat) -> some View {
        let availableWidth = size * 0.9  // Account for padding
        let colonWidth = size * 0.04
        let fieldSize = (availableWidth - (colonWidth * 2)) / 3  // 3 fields, 2 colons
        let fontSize = fieldSize * 0.65
        HStack(spacing: 0) {
            TimeDigitField(value: $timer.selectedHours, maxValue: 168, isFocused: focusedField == .hours, size: fieldSize, onSubmit: { timer.start() })
                .focused($focusedField, equals: .hours)
            Text(":")
                .font(.system(size: fontSize, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: colonWidth)
            TimeDigitField(value: $timer.selectedMinutes, maxValue: 99, isFocused: focusedField == .minutes, size: fieldSize, onSubmit: { timer.start() })
                .focused($focusedField, equals: .minutes)
            Text(":")
                .font(.system(size: fontSize, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: colonWidth)
            TimeDigitField(value: $timer.selectedSeconds, maxValue: 99, isFocused: focusedField == .seconds, size: fieldSize, onSubmit: { timer.start() })
                .focused($focusedField, equals: .seconds)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: timer.selectedHours) { _, _ in if focusedField != nil { selectedPreset = nil } }
        .onChange(of: timer.selectedMinutes) { _, _ in if focusedField != nil { selectedPreset = nil } }
        .onChange(of: timer.selectedSeconds) { _, _ in if focusedField != nil { selectedPreset = nil } }
    }

    @ViewBuilder
    private func soundLoopRow(padding: CGFloat, rowHeight: CGFloat) -> some View {
        let buttonHeight = rowHeight * 0.65
        let fontSize = rowHeight * 0.25
        let soundActive = timer.selectedAlarmSound != "No Sound"
        let durationActive = timer.alarmDuration != 5
        HStack(spacing: size * 0.02) {
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
                if soundActive {
                    HStack(spacing: rowHeight * 0.05) {
                        Image(systemName: "speaker.wave.2")
                            .font(.system(size: fontSize, weight: .medium))
                        Text(timer.selectedAlarmSound.replacingOccurrences(of: " (Default)", with: ""))
                            .font(.system(size: fontSize, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: buttonHeight)
                    .background(Capsule().fill(Color.white))
                } else {
                    Image(systemName: "speaker.slash")
                        .font(.system(size: fontSize, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: buttonHeight, height: buttonHeight)
                        .background(Circle().fill(Color(white: 0.2)))
                }
            }
            .buttonStyle(.plain)

            // Alarm length picker
            Menu {
                ForEach([1, 2, 3, 5, 10, 15, 30, 60], id: \.self) { seconds in
                    Button(seconds == 5 ? "5s (Default)" : "\(seconds)s") {
                        timer.alarmDuration = seconds
                    }
                }
            } label: {
                if durationActive {
                    HStack(spacing: rowHeight * 0.05) {
                        Image(systemName: "timer")
                            .font(.system(size: fontSize, weight: .medium))
                        Text("\(timer.alarmDuration)s")
                            .font(.system(size: fontSize, weight: .medium))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: buttonHeight)
                    .background(Capsule().fill(Color.white))
                } else {
                    Image(systemName: "timer")
                        .font(.system(size: fontSize, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: buttonHeight, height: buttonHeight)
                        .background(Circle().fill(Color(white: 0.2)))
                }
            }
            .buttonStyle(.plain)

            // Loop button
            Button(action: { timer.isLooping.toggle() }) {
                if timer.isLooping {
                    HStack(spacing: rowHeight * 0.05) {
                        Image(systemName: "repeat")
                            .font(.system(size: fontSize, weight: .medium))
                        Text("Loop")
                            .font(.system(size: fontSize, weight: .medium))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: buttonHeight)
                    .background(Capsule().fill(Color.white))
                } else {
                    Image(systemName: "repeat")
                        .font(.system(size: fontSize, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: buttonHeight, height: buttonHeight)
                        .background(Circle().fill(Color(white: 0.2)))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, padding)
    }

    @ViewBuilder
    private func startButton(padding: CGFloat, rowHeight: CGFloat) -> some View {
        Button(action: toggleTimer) {
            HStack(spacing: size * 0.02) {
                Image(systemName: "play.fill")
                    .font(.system(size: rowHeight * 0.4, weight: .medium))
                Text("Start Timer")
                    .font(.system(size: rowHeight * 0.35, weight: .medium))
            }
            .foregroundStyle(timer.totalSetSeconds == 0 ? .gray : .white)
            .frame(maxWidth: .infinity)
            .frame(height: rowHeight * 0.75)
            .background(Color(white: 0.2))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(timer.totalSetSeconds == 0)
        .padding(.horizontal, padding)
    }

    private var currentTimeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return "It's \(formatter.string(from: currentTime))."
    }

    @ViewBuilder
    private func alarmingStateView(padding: CGFloat) -> some View {
        let toolbarHeight = size / 6  // Fixed height for top/bottom rows
        let clockRowHeight = size * 0.5  // Dedicated row for bell circle
        let infoRowHeight = size - (toolbarHeight * 2) - clockRowHeight  // Remaining for info

        // Row 1: Toolbar - X, placeholder, label, placeholder, +
        HStack {
            Button(action: { dismissAlarmToClock() }) {
                Image(systemName: "arrowshape.backward.fill")
                    .font(.system(size: size * 0.05, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: size * 0.12, height: size * 0.12)
                    .background(Color(white: 0.2))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            // Placeholder to balance right side
            Color.clear.frame(width: size * 0.12, height: size * 0.12)

            Spacer()

            Text(timer.timerLabel.isEmpty || timer.timerLabel == "Timer" ? timer.defaultTimerName : timer.timerLabel)
                .font(.system(size: size * 0.06, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: size * 0.4)

            Spacer()

            // Placeholder to balance left side
            Color.clear.frame(width: size * 0.12, height: size * 0.12)

            if let onAdd = onAdd {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: size * 0.05, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: size * 0.12, height: size * 0.12)
                        .background(Color(white: 0.2))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: size * 0.12, height: size * 0.12)
            }
        }
        .padding(.horizontal, padding)
        .frame(maxWidth: .infinity)
        .frame(height: toolbarHeight)
        .border(showDebugBorders ? Color.red : Color.clear)

        // Row 2: Bell circle (own dedicated row)
        AlarmingCircleView(size: clockRowHeight * 0.95, isRinging: timer.isAlarmRinging)
            .onTapGesture {
                dismissAlarmToClock()
            }
            .frame(maxWidth: .infinity)
            .frame(height: clockRowHeight)
            .border(showDebugBorders ? Color.green : Color.clear)

        // Row 3: Alarm info text
        VStack(spacing: 2) {
            // Blinking "00:00:00 left" matching countdown view (VCR style blink - only digits blink)
            HStack(spacing: 0) {
                Text("00")
                Text(":")
                Text("00")
                Text(":")
                Text("00")
                Text(" left")
            }
            .opacity(timer.isAlarmRinging ? (blinkOn ? 1 : 0) : 1)
            .font(.system(size: infoRowHeight * 0.35, weight: .bold).monospacedDigit())
            .foregroundStyle(.white)
            .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
                if timer.isAlarmRinging {
                    blinkOn.toggle()
                } else {
                    blinkOn = true
                }
            }

            Text("\(formatDurationWords(timer.initialSetSeconds)) timer · \(getStartTimeString()) to \(getEndTimeString())")
                .font(.system(size: toolbarHeight * 0.18, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .frame(height: infoRowHeight)
        .border(showDebugBorders ? Color.yellow : Color.clear)

        // Bottom: Repeat button
        Button(action: {
            timer.dismissAlarm()
            // Always repeat the original duration, even for End At timers.
            timer.timeRemaining = timer.initialSetSeconds
            timer.startTime = Date()
            timer.endTime = Date().addingTimeInterval(timer.timeRemaining)
            timer.timerState = .running
        }) {
            HStack(spacing: size * 0.02) {
                Image(systemName: "repeat")
                    .font(.system(size: toolbarHeight * 0.4, weight: .medium))
                Text("Repeat Timer")
                    .font(.system(size: toolbarHeight * 0.35, weight: .medium))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: toolbarHeight * 0.75)
            .background(Color(white: 0.2))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, padding)
        .frame(maxWidth: .infinity)
        .frame(height: toolbarHeight)
        .border(showDebugBorders ? Color.purple : Color.clear)
    }

    @ViewBuilder
    private func runningPausedStateView(clockSize: CGFloat) -> some View {
        let padding = size * 0.025
        let toolbarHeight = size / 6  // Fixed height for top/bottom rows
        let clockRowHeight = size * 0.5  // Dedicated row for clock - SAME as alarming
        let infoRowHeight = size - (toolbarHeight * 2) - clockRowHeight  // Remaining for info
        let labelMaxWidth = size - (padding * 2) - (size * 0.12 * 4)

        // Row 1: Top bar - X, placeholder, label, gear, +
        HStack {
            Button(action: { showCancelConfirmation = true }) {
                Image(systemName: "arrowshape.backward.fill")
                    .font(.system(size: size * 0.05, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: size * 0.12, height: size * 0.12)
                    .background(Color(white: 0.2))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            // Placeholder to balance right side (gear + plus)
            Color.clear.frame(width: size * 0.12, height: size * 0.12)

            Spacer()

            Text(timer.timerLabel.isEmpty || timer.timerLabel == "Timer" ? timer.defaultTimerName : timer.timerLabel)
                .font(.system(size: size * 0.06, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .allowsTightening(true)
                .multilineTextAlignment(.center)
                .frame(maxWidth: labelMaxWidth)
                .onTapGesture { isEditingLabel = true }
                .popover(isPresented: $isEditingLabel) {
                    TextField("Timer", text: $timer.timerLabel)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                        .padding()
                }

            Spacer()

            Button(action: { showOptionsMenu = true }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: size * 0.05, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: size * 0.12, height: size * 0.12)
                    .background(Color(white: 0.2))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showOptionsMenu) {
                optionsMenuContent
            }

            if let onAdd = onAdd {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: size * 0.05, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: size * 0.12, height: size * 0.12)
                        .background(Color(white: 0.2))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: size * 0.12, height: size * 0.12)
            }
        }
        .padding(.horizontal, padding)
        .frame(maxWidth: .infinity)
        .frame(height: toolbarHeight)
        .opacity(0.75)
        .border(showDebugBorders ? Color.red : Color.clear)

        // Row 2: Clock (own dedicated row - matches alarming bell position)
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
            .frame(width: clockRowHeight * 0.95, height: clockRowHeight * 0.95)

            // Clockface badge under center dot
            Button(action: {
                if timer.useAutoClockface { timer.useAutoClockface = false }
                cycleClockface()
            }) {
                Text("\(timer.effectiveClockface.label) clockface")
                    .font(.system(size: size * 0.025, weight: .medium))
                    .foregroundStyle(.black.opacity(0.6))
            }
            .buttonStyle(.plain)
            .offset(y: size * 0.03)
        }
        .frame(maxWidth: .infinity)
        .frame(height: clockRowHeight)
        .border(showDebugBorders ? Color.green : Color.clear)

        // Row 3: Countdown + alarm info
        VStack(spacing: 2) {
            HStack(spacing: size * 0.02) {
                Image(systemName: "bell.fill")
                    .font(.system(size: infoRowHeight * 0.3, weight: .heavy))
                Text(formatDuration(timer.timeRemaining))
                    .font(.system(size: infoRowHeight * 0.35, weight: .bold).monospacedDigit())
                Text("left")
                    .font(.system(size: infoRowHeight * 0.35, weight: .bold))
            }
            .foregroundStyle(.white)

            Text("\(formatDurationWords(timer.initialSetSeconds)) timer · \(getStartTimeString()) to \(getEndTimeString())")
                .font(.system(size: toolbarHeight * 0.18, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .frame(height: infoRowHeight)
        .border(showDebugBorders ? Color.yellow : Color.clear)

        // Bottom: Pause button
        Button(action: toggleTimer) {
            HStack(spacing: size * 0.02) {
                Image(systemName: timer.timerState == .running ? "pause.fill" : "play.fill")
                    .font(.system(size: toolbarHeight * 0.4, weight: .medium))
                Text(timer.timerState == .running ? "Pause Timer" : "Resume Timer")
                    .font(.system(size: toolbarHeight * 0.35, weight: .medium))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: toolbarHeight * 0.75)
            .background(Color(white: 0.2))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, padding)
        .opacity(0.75)
        .frame(maxWidth: .infinity)
        .frame(height: toolbarHeight)
        .border(showDebugBorders ? Color.purple : Color.clear)
    }

    @ViewBuilder
    private var optionsMenuContent: some View {
        let rowCornerRadius: CGFloat = 8
        let rowBackground = Color.white.opacity(0.06)
        let rowBorder = Color.white.opacity(0.05)
        let menuCornerRadius: CGFloat = 12
        let menuBackground = Color(white: 0.12)
        let menuBorder = Color.white.opacity(0.08)

        VStack(alignment: .leading, spacing: 6) {
            // Sound picker
            Menu {
                ForEach(alarmSounds, id: \.self) { sound in
                    Button(sound) {
                        timer.selectedAlarmSound = sound
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: timer.selectedAlarmSound == "No Sound" ? "speaker.slash" : "speaker.wave.2")
                        .frame(width: 20)
                    Text("Sound")
                    Spacer()
                    let displayName = timer.selectedAlarmSound.replacingOccurrences(of: " (Default)", with: "")
                    Text(displayName == "No Sound" ? "Mute" : displayName)
                        .foregroundStyle(.white.opacity(0.5))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 9)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                        .fill(rowBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                        .stroke(rowBorder, lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Length picker
            Menu {
                ForEach([1, 2, 3, 5, 10, 15, 30, 60], id: \.self) { seconds in
                    Button("\(seconds)s") {
                        timer.alarmDuration = seconds
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "timer")
                        .frame(width: 20)
                    Text("Length")
                    Spacer()
                    Text("\(timer.alarmDuration)s")
                        .foregroundStyle(.white.opacity(0.5))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 9)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                        .fill(rowBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                        .stroke(rowBorder, lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Loop toggle
            HStack(spacing: 10) {
                Image(systemName: "repeat")
                    .frame(width: 20)
                Text("Loop")
                Spacer()
                Toggle("", isOn: $timer.isLooping)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                    .fill(rowBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                    .stroke(rowBorder, lineWidth: 1)
            )

            // Red toggle
            HStack(spacing: 10) {
                Image(systemName: "paintpalette")
                    .frame(width: 20)
                Text("Red")
                Spacer()
                Toggle("", isOn: $timer.useAutoColor)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                    .fill(rowBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                    .stroke(rowBorder, lineWidth: 1)
            )

            // Auto Zoom toggle
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .frame(width: 20)
                Text("Auto Zoom")
                Spacer()
                Toggle("", isOn: $timer.useAutoClockface)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                    .fill(rowBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                    .stroke(rowBorder, lineWidth: 1)
            )

            // Copy as Markdown button
            Button(action: { copyTimerAsMarkdown(); showOptionsMenu = false }) {
                HStack(spacing: 10) {
                    Image(systemName: "doc.on.doc")
                        .frame(width: 20)
                    Text("Copy as Markdown")
                    Spacer()
                }
                .padding(.vertical, 9)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                        .fill(rowBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                        .stroke(rowBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white)
        .padding(10)
        .frame(width: 230)
        .background(
            RoundedRectangle(cornerRadius: menuCornerRadius, style: .continuous)
                .fill(menuBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: menuCornerRadius, style: .continuous)
                .stroke(menuBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 12, x: 0, y: 6)
    }

    @ViewBuilder
    private var idleOptionsMenuContent: some View {
        let rowCornerRadius: CGFloat = 8
        let rowBackground = Color.white.opacity(0.06)
        let rowBorder = Color.white.opacity(0.05)
        let menuCornerRadius: CGFloat = 12
        let menuBackground = Color(white: 0.12)
        let menuBorder = Color.white.opacity(0.08)

        VStack(spacing: 6) {
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
                HStack(spacing: 10) {
                    Image(systemName: timer.selectedAlarmSound == "No Sound" ? "speaker.slash" : "speaker.wave.2")
                        .frame(width: 20)
                    Text("Sound")
                    Spacer()
                    let displayName = timer.selectedAlarmSound.replacingOccurrences(of: " (Default)", with: "")
                    Text(displayName == "No Sound" ? "Mute" : displayName)
                        .foregroundStyle(.white.opacity(0.5))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 9)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                        .fill(rowBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                        .stroke(rowBorder, lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Length picker
            Menu {
                ForEach([1, 2, 3, 5, 10, 15, 30, 60], id: \.self) { seconds in
                    Button(seconds == 5 ? "5s (Default)" : "\(seconds)s") {
                        timer.alarmDuration = seconds
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "timer")
                        .frame(width: 20)
                    Text("Length")
                    Spacer()
                    Text("\(timer.alarmDuration)s")
                        .foregroundStyle(.white.opacity(0.5))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 9)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                        .fill(rowBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                        .stroke(rowBorder, lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Loop toggle
            HStack(spacing: 10) {
                Image(systemName: "repeat")
                    .frame(width: 20)
                Text("Loop")
                Spacer()
                Toggle("", isOn: $timer.isLooping)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                    .fill(rowBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                    .stroke(rowBorder, lineWidth: 1)
            )

            // Copy as Markdown button
            Button(action: { copyTimerAsMarkdown(); showOptionsMenu = false }) {
                HStack(spacing: 10) {
                    Image(systemName: "doc.on.doc")
                        .frame(width: 20)
                    Text("Copy as Markdown")
                    Spacer()
                }
                .padding(.vertical, 9)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                        .fill(rowBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                        .stroke(rowBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white)
        .padding(10)
        .frame(width: 230)
        .background(
            RoundedRectangle(cornerRadius: menuCornerRadius, style: .continuous)
                .fill(menuBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: menuCornerRadius, style: .continuous)
                .stroke(menuBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 12, x: 0, y: 6)
    }

    var body: some View {
        let clockSize = size * 0.4
        let digitFontSize = size * 0.16
        let cornerRadius = size * 0.06
        let padding = size * 0.025

        VStack(spacing: 0) {
            if timer.timerState == .idle {
                idleStateView(padding: padding, digitFontSize: digitFontSize)
            } else if timer.timerState == .alarming {
                alarmingStateView(padding: padding)
            } else {
                runningPausedStateView(clockSize: clockSize)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(width: size, height: size)
        .background(Color(white: 0.1))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture {
            focusedField = nil
        }
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
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now in
            currentTime = now
        }
        .onAppear {
            // Clear focus to prevent visible field highlight
            focusedField = nil
            idleMode = timer.useEndAtMode ? .endAt : .countdown
            clockDisplayMode = .digital
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
    }

}

// MARK: - Current Time Slots View (read-only clock)
struct CurrentTimeSlotsView: View {
    let date: Date
    let cardSize: CGFloat

    private var blinkOn: Bool {
        let phase = Int(date.timeIntervalSinceReferenceDate / 3.0) % 2
        return phase == 0
    }

    private var timeParts: (hour: Int, minute: Int, isPM: Bool) {
        let calendar = Calendar.current
        let hour24 = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let isPM = hour24 >= 12
        var hour12 = hour24 % 12
        if hour12 == 0 { hour12 = 12 }
        return (hour12, minute, isPM)
    }

    var body: some View {
        let availableWidth = cardSize * 0.9
        let colonWidth = cardSize * 0.04
        let fieldSize = (availableWidth - (colonWidth * 2)) / 3
        let fontSize = fieldSize * 0.65

        HStack(spacing: 0) {
            TimeDigitDisplay(value: timeParts.hour, size: fieldSize)
            Text(":")
                .font(.system(size: fontSize, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: colonWidth)
                .opacity(blinkOn ? 1 : 0.2)
            TimeDigitDisplay(value: timeParts.minute, size: fieldSize)
            Text(timeParts.isPM ? "PM" : "AM")
                .font(.system(size: fieldSize * 0.72, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: fieldSize + colonWidth, height: fieldSize * 0.9)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Current Time Analog Clock View (read-only)
struct CurrentTimeClockFaceView: View {
    let date: Date

    private var hourAngle: Double {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date) % 12
        let minute = calendar.component(.minute, from: date)
        let second = calendar.component(.second, from: date)
        let fraction = (Double(hour) + Double(minute) / 60 + Double(second) / 3600) / 12
        return fraction * 360
    }

    private var minuteAngle: Double {
        let calendar = Calendar.current
        let minute = calendar.component(.minute, from: date)
        let second = calendar.component(.second, from: date)
        let fraction = (Double(minute) + Double(second) / 60) / 60
        return fraction * 360
    }

    private var secondAngle: Double {
        let calendar = Calendar.current
        let second = calendar.component(.second, from: date)
        return (Double(second) / 60) * 360
    }

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: size * 0.9, height: size * 0.9)

                ForEach(1...12, id: \.self) { value in
                    let angle = Double(value) / 12.0 * 360.0 - 90.0
                    let radius = size * 0.32
                    let x = radius * cos(angle * .pi / 180)
                    let y = radius * sin(angle * .pi / 180)
                    Text("\(value)")
                        .font(.system(size: size * 0.09, weight: .heavy))
                        .foregroundColor(.black)
                        .position(x: size / 2 + x, y: size / 2 + y)
                }

                ForEach(0..<12, id: \.self) { index in
                    let angle = Double(index) * 30.0
                    Rectangle()
                        .fill(Color.black.opacity(index % 3 == 0 ? 0.8 : 0.6))
                        .frame(width: size * 0.015, height: index % 3 == 0 ? size * 0.08 : size * 0.05)
                        .offset(y: -(size * 0.38))
                        .rotationEffect(.degrees(angle))
                }

                Rectangle()
                    .fill(Color.black.opacity(0.85))
                    .frame(width: size * 0.03, height: size * 0.22)
                    .offset(y: -(size * 0.11))
                    .rotationEffect(.degrees(hourAngle))

                Rectangle()
                    .fill(Color.black.opacity(0.85))
                    .frame(width: size * 0.02, height: size * 0.32)
                    .offset(y: -(size * 0.16))
                    .rotationEffect(.degrees(minuteAngle))

                Rectangle()
                    .fill(Color.black.opacity(0.7))
                    .frame(width: size * 0.01, height: size * 0.36)
                    .offset(y: -(size * 0.18))
                    .rotationEffect(.degrees(secondAngle))

                Circle()
                    .fill(Color.black)
                    .frame(width: size * 0.05, height: size * 0.05)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

struct ConeHandShape: Shape {
    func path(in rect: CGRect) -> Path {
        let size = min(rect.width, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let length = size * 0.35
        let baseWidth = size * 0.06

        var path = Path()
        path.move(to: CGPoint(x: center.x, y: center.y - length))
        path.addLine(to: CGPoint(x: center.x - baseWidth / 2, y: center.y + baseWidth * 0.15))
        path.addLine(to: CGPoint(x: center.x + baseWidth / 2, y: center.y + baseWidth * 0.15))
        path.closeSubpath()
        return path
    }
}

struct TimeDigitDisplay: View {
    let value: Int
    var size: CGFloat = 110

    var body: some View {
        let fieldWidth: CGFloat = size
        let fieldHeight: CGFloat = size * 0.9
        let fontSize: CGFloat = size * 0.72

        Text(String(format: "%02d", value))
            .font(.system(size: fontSize, weight: .bold).monospacedDigit())
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .frame(width: fieldWidth, height: fieldHeight)
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
                .font(.system(size: fontSize, weight: .bold).monospacedDigit())
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
    var isPulsing: Bool = false  // Throb animation for loop mode
    @State private var scale: CGFloat = 1.0

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
        clockfaceSeconds > 7200  // More than 2 hours = hour labels
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

    // Clock face opacity based on time of day
    // Noon = 100%, 6am/6pm = 75%, Midnight = 50%
    private var clockFaceOpacity: Double {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: Date())
        let minute = calendar.component(.minute, from: Date())
        let hourDecimal = Double(hour) + Double(minute) / 60.0

        // Sine wave: peaks at noon (12), troughs at midnight (0/24)
        // Maps 0-24 hours to 0-2π, with peak at π/2 (noon)
        let radians = (hourDecimal - 6) * .pi / 12  // Shift so noon is at peak
        let normalized = (sin(radians) + 1) / 2  // 0 to 1

        // Scale from 0.5 (midnight) to 1.0 (noon)
        return 0.5 + normalized * 0.5
    }

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)

            ZStack {
                // Background circle (white) - opacity based on time of day
                Circle()
                    .fill(Color.white.opacity(clockFaceOpacity))
                    .frame(width: size * 0.9, height: size * 0.9)

                // Pie (remaining time) - shrinks CW from 12 o'clock
                if remainingSeconds > 0 {
                    let angle = (remainingSeconds / clockMaxSeconds) * 360
                    PieSlice(
                        startAngle: .degrees(-90),
                        endAngle: .degrees(-90 - angle),
                        clockwise: true
                    )
                    .fill(pieColor)
                    .frame(width: size * 0.9, height: size * 0.9)
                }

                // Tick marks - drawn on top of pie
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
                        .offset(y: -(size * 0.42))
                        .rotationEffect(.degrees(majorAngle))

                    // Minor ticks between labels
                    ForEach(1...minorTicksPerSegment, id: \.self) { j in
                        let minorAngle = majorAngle + (segmentSize * Double(j) / Double(minorTicksPerSegment + 1))
                        Rectangle()
                            .fill(Color.black.opacity(0.7))
                            .frame(width: size * 0.008, height: size * 0.03)
                            .offset(y: -(size * 0.43))
                            .rotationEffect(.degrees(minorAngle))
                    }
                }

                // Number labels (CCW from top) - inside the clock
                ForEach(clockLabels, id: \.self) { value in
                    let position = Double(value) / Double(maxValue)
                    let angle = -position * 360.0 - 90  // CCW
                    let radius = size * 0.32  // Inside the clock edge
                    let x = radius * cos(angle * .pi / 180)
                    let y = radius * sin(angle * .pi / 180)
                    let label = value == 0 ? (isHourScale ? "0h" : "0m") : "\(value)"
                    Text(label)
                        .font(.system(size: size * 0.09, weight: .heavy))
                        .foregroundColor(.black)
                        .position(x: size/2 + x, y: size/2 + y)
                }

                // Center dot
                Circle()
                    .fill(Color.black)
                    .frame(width: size * 0.04, height: size * 0.04)
            }
            .scaleEffect(scale)
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
            .onAppear {
                if isPulsing {
                    startPulsing()
                }
            }
            .onChange(of: isPulsing) { _, newValue in
                if newValue {
                    startPulsing()
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        scale = 1.0
                    }
                }
            }
        }
    }

    private func startPulsing() {
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            scale = 1.15
        }
    }
}

// MARK: - Alarming Circle View (pulsing animation)
struct AlarmingCircleView: View {
    let size: CGFloat
    let isRinging: Bool
    @State private var scale: CGFloat = 1.0

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.orange)
                .frame(width: size * 0.9, height: size * 0.9)
                .scaleEffect(scale)

            Image(systemName: "bell.fill")
                .font(.system(size: size * 0.55, weight: .light))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .onAppear {
            if isRinging {
                startPulsing()
            }
        }
        .onChange(of: isRinging) { _, newValue in
            if newValue {
                startPulsing()
            } else {
                stopPulsing()
            }
        }
    }

    private func startPulsing() {
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            scale = 1.15
        }
    }

    private func stopPulsing() {
        withAnimation(.easeInOut(duration: 0.2)) {
            scale = 1.0
        }
    }
}

// MARK: - Throbbing Bell View (pulsing animation for alarming)
struct ThrobbingBellView: View {
    let size: CGFloat
    let isRinging: Bool
    @State private var scale: CGFloat = 1.0

    var body: some View {
        Image(systemName: "bell.fill")
            .font(.system(size: size, weight: .light))
            .foregroundStyle(.white)
            .scaleEffect(scale)
            .onAppear {
                if isRinging {
                    startPulsing()
                }
            }
            .onChange(of: isRinging) { _, newValue in
                if newValue {
                    startPulsing()
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        scale = 1.0
                    }
                }
            }
    }

    private func startPulsing() {
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            scale = 1.15
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
