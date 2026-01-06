import SwiftUI
import Combine
import AppKit

// MARK: - Timer Model
class TimerModel: ObservableObject, Identifiable {
    let id = UUID()
    @Published var selectedHours = 0
    @Published var selectedMinutes = 15
    @Published var selectedSeconds = 0
    @Published var timerState: TimerState = .idle
    @Published var timeRemaining: TimeInterval = 0
    @Published var endTime: Date?
    @Published var timerLabel: String = "Timer"
    @Published var selectedAlarmSound: String = "Radial (Default)"
    @Published var selectedClockface: ClockfaceScale = .hours168

    enum TimerState { case idle, running, paused }

    var totalSetSeconds: TimeInterval {
        TimeInterval(selectedHours * 3600 + selectedMinutes * 60 + selectedSeconds)
    }

    func start() {
        guard totalSetSeconds > 0 else { return }
        timeRemaining = totalSetSeconds
        endTime = Date().addingTimeInterval(totalSetSeconds)
        timerState = .running
        selectedClockface = ClockfaceScale.allCases.last { $0.seconds >= totalSetSeconds } ?? .hours168
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

    func update() {
        guard timerState == .running, let end = endTime else { return }
        let remaining = end.timeIntervalSinceNow
        if remaining <= 0 {
            timeRemaining = 0
            timerState = .idle
            NSSound.beep()
        } else {
            timeRemaining = remaining
        }
    }
}

// MARK: - Clockface Scale (top level)
enum ClockfaceScale: CaseIterable {
    case hours168, hours96, hours72, hours48, hours24, minutes120, minutes60, minutes15, minutes5

    var seconds: Double {
        switch self {
        case .hours168: return 168 * 3600
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
        case .hours168: return "168 hr"
        case .hours96: return "96 hr"
        case .hours72: return "72 hr"
        case .hours48: return "48 hr"
        case .hours24: return "24 hr"
        case .minutes120: return "120 min"
        case .minutes60: return "60 min"
        case .minutes15: return "15 min"
        case .minutes5: return "5 min"
        }
    }
}

// MARK: - Main View
struct ContentView: View {
    @State private var timers: [TimerModel] = [TimerModel()]
    let globalTimer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    private let spacing: CGFloat = 8
    private let columnCount = 2
    private let baseCardSize: CGFloat = 200

    private var rowCount: Int {
        Int(ceil(Double(timers.count + 1) / Double(columnCount)))
    }

    private func resizeWindow() {
        guard let window = NSApplication.shared.windows.first else { return }
        let newWidth = CGFloat(columnCount) * baseCardSize + spacing * CGFloat(columnCount + 1)
        let newHeight = CGFloat(rowCount) * baseCardSize + spacing * CGFloat(rowCount + 1) + 28 // 28 for title bar

        var frame = window.frame
        let oldHeight = frame.height
        frame.size = NSSize(width: newWidth, height: newHeight)
        // Keep top-left corner in place
        frame.origin.y += oldHeight - newHeight
        window.setFrame(frame, display: true, animate: true)
    }

    var body: some View {
        GeometryReader { geo in
            let itemCount = timers.count + 1

            // Calculate columns and rows based on window size
            let cols = max(1, Int((geo.size.width + spacing) / (baseCardSize + spacing)))
            let rows = max(1, Int((geo.size.height + spacing) / (baseCardSize + spacing)))

            // Card size to fill available space
            let availableWidth = geo.size.width - spacing * CGFloat(cols + 1)
            let availableHeight = geo.size.height - spacing * CGFloat(rows + 1)
            let cardSize = min(availableWidth / CGFloat(cols), availableHeight / CGFloat(rows))

            let columns = Array(repeating: GridItem(.fixed(cardSize), spacing: spacing), count: cols)

            let gridWidth = CGFloat(cols) * cardSize + CGFloat(cols - 1) * spacing
            let gridHeight = CGFloat(rows) * cardSize + CGFloat(rows - 1) * spacing

            // Use HStack of VStacks for explicit grid layout with centering
            let allItems = timers.count + 1
            let actualCols = min(cols, allItems)  // Don't show more columns than items
            let actualRows = Int(ceil(Double(allItems) / Double(actualCols)))
            let actualGridWidth = CGFloat(actualCols) * cardSize + CGFloat(actualCols - 1) * spacing
            let actualGridHeight = CGFloat(actualRows) * cardSize + CGFloat(actualRows - 1) * spacing

            VStack(spacing: spacing) {
                ForEach(0..<actualRows, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(0..<actualCols, id: \.self) { col in
                            let index = row * actualCols + col
                            if index < timers.count {
                                TimerCardView(timer: timers[index], compact: true, size: cardSize, onDelete: {
                                    withAnimation {
                                        timers.remove(at: index)
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        resizeWindow()
                                    }
                                })
                                .frame(width: cardSize, height: cardSize)
                            } else if index == timers.count {
                                // Add button
                                Button(action: {
                                    withAnimation {
                                        timers.append(TimerModel())
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        resizeWindow()
                                    }
                                }) {
                                    RoundedRectangle(cornerRadius: cardSize * 0.06)
                                        .fill(Color(white: 0.1))
                                        .overlay(
                                            Image(systemName: "plus")
                                                .font(.system(size: cardSize * 0.2, weight: .light))
                                                .foregroundColor(.gray)
                                        )
                                }
                                .buttonStyle(.plain)
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
        .onReceive(globalTimer) { _ in
            for timer in timers {
                timer.update()
            }
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

    private var scale: CGFloat { size / 200 }  // Base size is 200

    let alarmSounds = [
        "Radial (Default)", "Arpeggio", "Breaking", "Canopy", "Chalet",
        "Chirp", "Daybreak", "Departure", "Dollop", "Journey", "Kettle",
        "Beacon", "Bulletin", "Chimes", "Circuit", "Constellation",
        "Cosmic", "Crystals", "Hillside", "Illuminate", "Night Owl",
        "Opening", "Playtime", "Presto", "Radar", "Sencha", "Signal",
        "Silk", "Slow Rise", "Stargaze", "Summit", "Twinkle", "Uplift"
    ]

    var availableClockfaces: [ClockfaceScale] {
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

    enum TimeField: Hashable {
        case hours, minutes, seconds, label
    }

    var rightButtonLabel: String {
        switch timer.timerState {
        case .idle, .paused: return "Start"
        case .running: return "Pause"
        }
    }

    var rightButtonColor: Color {
        switch timer.timerState {
        case .idle, .paused: return .green
        case .running: return .orange
        }
    }

    func toggleTimer() {
        switch timer.timerState {
        case .idle: timer.start()
        case .running: timer.pause()
        case .paused: timer.resume()
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
                        Text(":").font(.system(size: digitFontSize, weight: .thin)).foregroundStyle(.white)
                        TimeDigitField(value: $timer.selectedMinutes, maxValue: 59, isFocused: focusedField == .minutes, size: size * 0.22, onSubmit: { timer.start() })
                            .focused($focusedField, equals: .minutes)
                        Text(":").font(.system(size: digitFontSize, weight: .thin)).foregroundStyle(.white)
                        TimeDigitField(value: $timer.selectedSeconds, maxValue: 59, isFocused: focusedField == .seconds, size: size * 0.22, onSubmit: { timer.start() })
                            .focused($focusedField, equals: .seconds)
                    }
                } else {
                    // Running/Paused: show clock and countdown
                    AnalogTimerView(
                        remainingSeconds: timer.timeRemaining,
                        clockfaceSeconds: timer.selectedClockface.seconds,
                        onSetTime: { seconds in
                            timer.timeRemaining = max(1, seconds)
                            timer.endTime = Date().addingTimeInterval(seconds)
                        }
                    )
                    .frame(width: clockSize, height: clockSize)

                    Text(formatDuration(timer.timeRemaining))
                        .font(.system(size: countdownFontSize, weight: .thin))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
            }

            // Clockface toggle - top right (only when running/paused)
            if timer.timerState != .idle {
                VStack {
                    HStack {
                        Spacer()
                        Button(action: cycleClockface) {
                            Text(timer.selectedClockface.label)
                                .font(.system(size: size * 0.035, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, size * 0.04)
                                .padding(.vertical, size * 0.02)
                                .background(Color.gray.opacity(0.3))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(padding)
            }

            // Bottom buttons - Delete/Cancel left, Start/Pause right
            VStack {
                Spacer()
                HStack {
                    Button(action: {
                        if timer.timerState == .idle {
                            onDelete?()
                        } else {
                            timer.cancel()
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
        }
        .frame(width: size, height: size)
        .background(Color(white: 0.1))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture {
            focusedField = nil
        }
        .onAppear {
            focusedField = nil
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

    var body: some View {
        let fieldWidth: CGFloat = size
        let fieldHeight: CGFloat = size * 0.9
        let fontSize: CGFloat = size * 0.72

        ZStack {
            // Background - always present, orange when focused
            RoundedRectangle(cornerRadius: size * 0.07)
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
                RoundedRectangle(cornerRadius: 8)
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
        case 168: return stride(from: 0, to: 168, by: 14).map { $0 }  // 12 labels
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
                    .fill(Color.red)
                    .frame(width: size * 0.63, height: size * 0.63)
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
