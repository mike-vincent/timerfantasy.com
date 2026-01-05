import SwiftUI
import AVFoundation

struct TimerView: View {
    @State private var totalSeconds: Double = 0
    @State private var remainingSeconds: Double = 0
    @State private var isRunning = false
    @State private var timer: Timer?
    @State private var isDragging = false
    @State private var maxMinutes: Double = 60

    // Even numbers only for max time options
    private let maxTimeOptions: [Int] = [10, 20, 30, 60, 90, 120, 180, 240]

    // Computed tick marks based on maxMinutes (always 12 divisions)
    private var tickMarks: [Int] {
        let interval = Int(maxMinutes) / 12
        return (0..<12).map { $0 * interval }
    }

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let radius = size / 2 - 20

            ZStack {
                // Background circle (gray)
                Circle()
                    .fill(Color(white: 0.95))
                    .frame(width: size - 40, height: size - 40)

                // Red pie (remaining time - starts at 0/left, grows CW)
                if remainingSeconds > 0 {
                    let remainingAngle = (remainingSeconds / (maxMinutes * 60)) * 360
                    // 0 is at 180° (left/9 o'clock), grows CW (positive direction in SwiftUI)
                    PieSlice(
                        startAngle: .degrees(180),
                        endAngle: .degrees(180 + remainingAngle),
                        clockwise: false
                    )
                    .fill(Color.red.opacity(0.85))
                    .frame(width: size - 44, height: size - 44)
                }

                // Tick marks and numbers (0 at left, ascending clockwise: 0, 5, 10, 15...)
                ForEach(tickMarks, id: \.self) { minute in
                    let angle = angleForMinute(minute)
                    let numberRadius = radius - 25

                    // Tick mark
                    Rectangle()
                        .fill(Color.gray)
                        .frame(width: 2, height: minute % Int(maxMinutes / 4) == 0 ? 15 : 8)
                        .offset(y: -radius + (minute % Int(maxMinutes / 4) == 0 ? 7.5 : 4))
                        .rotationEffect(.degrees(angle))

                    // Number label
                    Text("\(minute)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.black)
                        .position(
                            x: center.x + numberRadius * CGFloat(cos((angle - 90) * .pi / 180)),
                            y: center.y + numberRadius * CGFloat(sin((angle - 90) * .pi / 180))
                        )
                }

                // Center dot
                Circle()
                    .fill(Color.black)
                    .frame(width: 12, height: 12)

                // Time display
                VStack {
                    Spacer()
                    Text(formatTime(remainingSeconds))
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.bottom, 40)
                }
                .frame(width: size - 40, height: size - 40)

                // Max time picker (bottom right)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Menu {
                            ForEach(maxTimeOptions, id: \.self) { minutes in
                                Button("\(minutes)m") {
                                    resetTimer()
                                    maxMinutes = Double(minutes)
                                }
                            }
                        } label: {
                            Text("\(Int(maxMinutes))m")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.gray)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.8))
                                .cornerRadius(4)
                        }
                        .menuStyle(.borderlessButton)
                    }
                }
                .padding(8)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleDrag(value: value, center: center, radius: radius)
                    }
                    .onEnded { _ in
                        isDragging = false
                        if totalSeconds > 0 && !isRunning {
                            startTimer()
                        }
                    }
            )
            .onTapGesture(count: 2) {
                resetTimer()
            }
        }
    }

    // 0 at left (180°), numbers go CW ascending: 0, 5, 10, 15...
    private func angleForMinute(_ minute: Int) -> Double {
        // 180° + (minute/maxMinutes * 360)
        return 180 + (Double(minute) / maxMinutes) * 360
    }

    private func handleDrag(value: DragGesture.Value, center: CGPoint, radius: CGFloat) {
        isDragging = true
        stopTimer()

        let vector = CGVector(
            dx: value.location.x - center.x,
            dy: value.location.y - center.y
        )

        // Calculate angle from left (0 position at 180°), going CW
        var angle = atan2(vector.dy, vector.dx) * 180 / .pi  // Standard angle from right
        // Convert to angle from left (0 position): subtract 180
        angle = angle - 180
        if angle < 0 { angle += 360 }

        // Convert angle to minutes (0° from left = 0 min, 360° = maxMinutes)
        let minutes = angle / 360 * maxMinutes
        let seconds = minutes * 60

        // Snap to nearest 30 seconds for easier setting
        let snappedSeconds = (seconds / 30).rounded() * 30

        totalSeconds = snappedSeconds
        remainingSeconds = snappedSeconds
    }

    private func startTimer() {
        isRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if remainingSeconds > 0 {
                remainingSeconds -= 0.1
            } else {
                remainingSeconds = 0
                stopTimer()
                playCompletionSound()
            }
        }
    }

    private func stopTimer() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    private func resetTimer() {
        stopTimer()
        totalSeconds = 0
        remainingSeconds = 0
    }

    private func playCompletionSound() {
        NSSound.beep()
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
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
    TimerView()
        .frame(width: 300, height: 300)
        .padding()
}
