import SwiftUI
import Combine
import AppKit

// MARK: - Main View
struct ContentView: View {
    @State private var selectedTab = "VincentTimer"

    var body: some View {
        NavigationStack {
            ClockTimerView()
                .preferredColorScheme(.dark)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Picker("", selection: $selectedTab) {
                            Text("VincentTimer").tag("VincentTimer")
                        }
                        .pickerStyle(.segmented)
                        .fixedSize()
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: {
                            // Add new timer action
                        }) {
                            Image(systemName: "plus")
                        }
                    }
                }
                .toolbarBackground(.black, for: .windowToolbar)
                .toolbarColorScheme(.dark, for: .windowToolbar)
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

// MARK: - Timer View
struct ClockTimerView: View {
    @State private var selectedHours = 0
    @State private var selectedMinutes = 15
    @State private var selectedSeconds = 0

    @State private var timerState: TimerState = .idle
    @State private var totalDuration: TimeInterval = 0
    @State private var timeRemaining: TimeInterval = 0
    @State private var endTime: Date?
    @State private var recentTimers: [RecentTimer] = []
    @State private var timerLabel: String = "Timer"
    @State private var selectedAlarmSound: String = "Radial (Default)"
    @State private var selectedClockface: ClockfaceScale = .hours168

    let alarmSounds = [
        "Radial (Default)", "Arpeggio", "Breaking", "Canopy", "Chalet",
        "Chirp", "Daybreak", "Departure", "Dollop", "Journey", "Kettle",
        "Beacon", "Bulletin", "Chimes", "Circuit", "Constellation",
        "Cosmic", "Crystals", "Hillside", "Illuminate", "Night Owl",
        "Opening", "Playtime", "Presto", "Radar", "Sencha", "Signal",
        "Silk", "Slow Rise", "Stargaze", "Summit", "Twinkle", "Uplift"
    ]

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

    var availableClockfaces: [ClockfaceScale] {
        ClockfaceScale.allCases.filter { $0.seconds >= timeRemaining }
    }

    func cycleClockface() {
        let available = availableClockfaces
        guard !available.isEmpty else { return }
        if let currentIndex = available.firstIndex(of: selectedClockface) {
            let nextIndex = (currentIndex + 1) % available.count
            selectedClockface = available[nextIndex]
        } else {
            // Current selection not valid, pick smallest valid
            selectedClockface = available.last ?? .hours24
        }
    }

    let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    // Computed property for setting time in seconds
    var setSeconds: Binding<TimeInterval> {
        Binding(
            get: { TimeInterval(selectedHours * 3600 + selectedMinutes * 60 + selectedSeconds) },
            set: { newValue in
                let total = Int(newValue)
                selectedHours = total / 3600
                selectedMinutes = (total % 3600) / 60
                selectedSeconds = total % 60
            }
        )
    }

    var maxSeconds: TimeInterval {
        168 * 3600 // 168 hours max (1 week)
    }

    enum TimerState {
        case idle
        case running
        case paused
    }

    @FocusState private var focusedField: TimeField?

    enum TimeField: Hashable {
        case hours, minutes, seconds, label
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Time Input Display
            if timerState == .idle {
                // Labels row
                HStack(spacing: 0) {
                    Text("hr")
                        .frame(width: 120)
                    Text("min")
                        .frame(width: 120)
                    Text("sec")
                        .frame(width: 120)
                }
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.gray)
                .padding(.bottom, 8)

                // Clickable digits
                HStack(spacing: 0) {
                    // Hours
                    TimeDigitField(value: $selectedHours, maxValue: 168, isFocused: focusedField == .hours)
                        .focused($focusedField, equals: .hours)

                    Text(":")
                        .font(.system(size: 80, weight: .thin))
                        .foregroundStyle(.white)

                    // Minutes
                    TimeDigitField(value: $selectedMinutes, maxValue: 59, isFocused: focusedField == .minutes)
                        .focused($focusedField, equals: .minutes)

                    Text(":")
                        .font(.system(size: 80, weight: .thin))
                        .foregroundStyle(.white)

                    // Seconds
                    TimeDigitField(value: $selectedSeconds, maxValue: 59, isFocused: focusedField == .seconds)
                        .focused($focusedField, equals: .seconds)
                }
            } else {
                // Running/Paused: show clock and countdown
                AnalogTimerView(
                    remainingSeconds: timeRemaining,
                    clockfaceSeconds: selectedClockface.seconds,
                    onSetTime: timerState == .paused ? { newSeconds in
                        setTimeFromSeconds(newSeconds)
                    } : nil
                )
                .frame(width: 220, height: 220)
                .padding(.bottom, 20)

                Text(formatDuration(timeRemaining))
                    .font(.system(size: 60, weight: .thin))
                    .monospacedDigit()
                    .foregroundStyle(.white)

                if let end = endTime {
                    HStack(spacing: 4) {
                        Image(systemName: "bell.fill")
                            .font(.caption)
                        Text(getEndTimeString())
                            .font(.subheadline)
                    }
                    .foregroundStyle(.gray)
                    .padding(.top, 8)
                }

                // Clockface cycle button
                Button(action: cycleClockface) {
                    Text(selectedClockface.label)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.gray.opacity(0.3))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
            }

            // Timer label and options (only when idle)
            if timerState == .idle {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Timer", text: $timerLabel)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                        .focused($focusedField, equals: .label)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 9)
                        .onChange(of: focusedField) { _, newValue in
                            if newValue == .label && timerLabel == "Timer" {
                                timerLabel = ""
                            }
                        }

                    // Alarm sound picker
                    Picker("", selection: $selectedAlarmSound) {
                        ForEach(alarmSounds, id: \.self) { sound in
                            Text(sound).tag(sound)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .fixedSize(horizontal: true, vertical: false)
                .padding(.top, 30)
                .padding(.bottom, 40)
            }

            Spacer()

            // Control Buttons (pill style)
            HStack(spacing: 20) {
                Button(action: cancelTimer) {
                    Text("Cancel")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(timerState == .idle ? .gray : .white)
                        .frame(width: 140, height: 50)
                        .background(Color(white: 0.2))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(timerState == .idle)

                Button(action: toggleTimer) {
                    Text(rightButtonLabel)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(timerState == .idle && setSeconds.wrappedValue == 0 ? .gray : rightButtonColor)
                        .frame(width: 140, height: 50)
                        .background(rightButtonColor.opacity(timerState == .idle && setSeconds.wrappedValue == 0 ? 0.1 : 0.3))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(timerState == .idle && setSeconds.wrappedValue == 0)
            }
            .padding(.bottom, 40)

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .contentShape(Rectangle())
        .onTapGesture {
            // Unfocus when tapping background
            focusedField = nil
        }
        .onReceive(timer) { _ in
            updateTimer()
        }
    }

    func startRecent(_ recent: RecentTimer) {
        selectedHours = recent.hours
        selectedMinutes = recent.minutes
        selectedSeconds = recent.seconds
        toggleTimer()
    }

    var rightButtonLabel: String {
        switch timerState {
            case .idle, .paused: return "Start"
            case .running: return "Pause"
        }
    }

    var rightButtonColor: Color {
        switch timerState {
            case .idle, .paused: return .green
            case .running: return .orange
        }
    }

    func toggleTimer() {
        switch timerState {
            case .idle:
                totalDuration = TimeInterval(selectedHours * 3600 + selectedMinutes * 60 + selectedSeconds)
                guard totalDuration > 0 else { return }
                timeRemaining = totalDuration
                endTime = Date().addingTimeInterval(totalDuration)
                timerState = .running
                // Auto-select smallest clockface that fits
                selectedClockface = ClockfaceScale.allCases.last { $0.seconds >= totalDuration } ?? .hours168
                addToRecents()

            case .running:
                timerState = .paused

            case .paused:
                endTime = Date().addingTimeInterval(timeRemaining)
                timerState = .running
        }
    }

    func addToRecents() {
        let newRecent = RecentTimer(hours: selectedHours, minutes: selectedMinutes, seconds: selectedSeconds)
        // Remove duplicate if exists
        recentTimers.removeAll { $0.hours == newRecent.hours && $0.minutes == newRecent.minutes && $0.seconds == newRecent.seconds }
        // Add to front
        recentTimers.insert(newRecent, at: 0)
        // Keep only last 5
        if recentTimers.count > 5 {
            recentTimers = Array(recentTimers.prefix(5))
        }
    }

    func cancelTimer() {
        timerState = .idle
        timeRemaining = 0
        endTime = nil
    }

    func updateTimer() {
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
        guard let end = endTime else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: end)
    }

    func setTimeFromSeconds(_ seconds: Double) {
        // When paused, update timeRemaining directly
        timeRemaining = max(1, seconds)  // At least 1 second
        // Also update the selected values for when timer is reset
        let total = Int(seconds)
        selectedHours = total / 3600
        selectedMinutes = (total % 3600) / 60
        selectedSeconds = total % 60
    }
}

// MARK: - Time Digit Field (clickable number input)
struct TimeDigitField: View {
    @Binding var value: Int
    let maxValue: Int
    let isFocused: Bool
    @State private var textValue: String = ""
    @State private var isEditing: Bool = false
    @State private var hasTyped: Bool = false

    var body: some View {
        ZStack {
            // Background - always present, orange when focused
            RoundedRectangle(cornerRadius: 8)
                .fill(isFocused ? Color.orange : Color.clear)
                .frame(width: 110, height: 100)

            TextField("", text: $textValue)
                .font(.system(size: 80, weight: .thin))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(width: 110, height: 100)
                .textFieldStyle(.plain)
                .tint(.clear)
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
        let hours = clockfaceSeconds / 3600

        if hours >= 24 {
            // Large hour scales: divide into 4 quadrants
            let step = max(Int(hours) / 4, 1)
            return stride(from: 0, to: Int(hours), by: step).map { $0 }
        } else if mins == 120 {
            // 120m: show every 10 minutes (0, 10, 20, ... 110)
            return stride(from: 0, to: 120, by: 10).map { $0 }
        } else if mins == 60 {
            // 60m: show every 5 minutes
            return stride(from: 0, to: 60, by: 5).map { $0 }
        } else if mins == 15 {
            // 15m: show 0, 5, 10
            return [0, 5, 10]
        } else if mins == 5 {
            // 5m: show 0, 1, 2, 3, 4
            return [0, 1, 2, 3, 4]
        } else if hours >= 1 {
            // Other hour scales
            let step = max(Int(hours) / 4, 1)
            return stride(from: 0, to: Int(hours), by: step).map { $0 }
        } else {
            // Other minute scales
            let step = max(mins / 4, 1)
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
                // Background circle (white)
                Circle()
                    .fill(Color.white)
                    .frame(width: size - 40, height: size - 40)

                // Red pie (remaining time) - shrinks CW from 12 o'clock
                if remainingSeconds > 0 {
                    let angle = (remainingSeconds / clockMaxSeconds) * 360
                    PieSlice(
                        startAngle: .degrees(-90),
                        endAngle: .degrees(-90 - angle),
                        clockwise: true
                    )
                    .fill(Color.red)
                    .frame(width: size - 44, height: size - 44)
                }

                // Tick marks - 60 ticks inside circle edge
                ForEach(0..<60, id: \.self) { i in
                    let angle = Double(i) * 6.0  // 360/60 = 6 degrees per tick
                    let isMajor = i % 5 == 0  // Major tick every 5
                    Rectangle()
                        .fill(Color.black.opacity(0.7))
                        .frame(width: isMajor ? 2 : 1, height: isMajor ? size * 0.08 : size * 0.04)
                        .offset(y: -(size / 2 - 32))  // Inside the circle
                        .rotationEffect(.degrees(angle))
                }

                // Number labels (CCW from top) - outside the circle
                ForEach(clockLabels, id: \.self) { value in
                    let position = Double(value) / Double(maxValue)
                    let angle = -position * 360.0 - 90  // CCW
                    let radius = (size / 2) + 12  // Outside the circle
                    let x = radius * cos(angle * .pi / 180)
                    let y = radius * sin(angle * .pi / 180)
                    Text("\(value)")
                        .font(.system(size: 12, weight: .bold))
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
