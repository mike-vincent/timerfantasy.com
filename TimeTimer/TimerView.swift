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

                // Red pie (remaining time - grows CCW from 0, shrinks as time passes)
                if remainingSeconds > 0 {
                    let remainingAngle = (remainingSeconds / (maxMinutes * 60)) * 360
                    PieSlice(
                        startAngle: .degrees(-90),
                        endAngle: .degrees(-90 - remainingAngle),
                        clockwise: false
                    )
                    .fill(Color.red.opacity(0.85))
                    .frame(width: size - 44, height: size - 44)
                }

                // Tick marks and numbers (0 at top, CCW ascending: 0, 5, 10, 15...)
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
                            x: center.x + numberRadius * CGFloat(sin(angle * .pi / 180)),
                            y: center.y - numberRadius * CGFloat(cos(angle * .pi / 180))
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

    // Numbers go CCW from 0 at top: 0, 5, 10, 15... (ascending, going left/CCW)
    private func angleForMinute(_ minute: Int) -> Double {
        // Negative angle = CCW from top
        return -(Double(minute) / maxMinutes) * 360
    }

    private func handleDrag(value: DragGesture.Value, center: CGPoint, radius: CGFloat) {
        isDragging = true
        stopTimer()

        let vector = CGVector(
            dx: value.location.x - center.x,
            dy: value.location.y - center.y
        )

        // Calculate angle from top (0°), going CCW (negative direction)
        var angle = atan2(vector.dx, -vector.dy) * 180 / .pi
        // Convert CW angle to CCW: if angle is negative (left side), it's our positive time
        // If angle is positive (right side), convert to negative equivalent
        if angle > 0 { angle = angle - 360 }
        // Now angle is negative (CCW from top), convert to positive minutes
        let ccwAngle = -angle  // Make positive

        // Convert angle to minutes (0° = 0 min, 360° = maxMinutes)
        let minutes = ccwAngle / 360 * maxMinutes
        let seconds = minutes * 60

        // Snap to nearest 30 seconds for easier setting
        let snappedSeconds = (seconds / 30).rounded() * 30

        totalSeconds = min(snappedSeconds, maxMinutes * 60)
        remainingSeconds = min(snappedSeconds, maxMinutes * 60)
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
