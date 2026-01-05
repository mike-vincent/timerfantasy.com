import SwiftUI
import AVFoundation

struct TimerView: View {
    @State private var totalSeconds: Double = 0
    @State private var remainingSeconds: Double = 0
    @State private var isRunning = false
    @State private var timer: Timer?
    @State private var isDragging = false

    private let maxMinutes: Double = 60
    private let tickMarks = [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55]

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let radius = size / 2 - 20

            ZStack {
                // Background circle
                Circle()
                    .fill(Color(white: 0.95))
                    .frame(width: size - 40, height: size - 40)

                // Red pie (remaining time)
                if remainingSeconds > 0 {
                    PieSlice(
                        startAngle: .degrees(-90),
                        endAngle: .degrees(-90 + (remainingSeconds / (maxMinutes * 60)) * 360)
                    )
                    .fill(Color.red.opacity(0.85))
                    .frame(width: size - 44, height: size - 44)
                }

                // Tick marks and numbers (descending clockwise: 0, 55, 50, 45...)
                ForEach(tickMarks, id: \.self) { minute in
                    let angle = angleForMinute(minute)
                    let numberRadius = radius - 25

                    // Tick mark
                    Rectangle()
                        .fill(Color.gray)
                        .frame(width: 2, height: minute % 15 == 0 ? 15 : 8)
                        .offset(y: -radius + (minute % 15 == 0 ? 7.5 : 4))
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

    // Numbers go clockwise but descending: 0 at top, then 55, 50, 45...
    // So 0 min = 0°, 5 min = 30°, 10 min = 60°, etc.
    private func angleForMinute(_ minute: Int) -> Double {
        // Convert minute to angle: 0->0°, 5->30°, 10->60°...
        // But we want descending, so 0 at top, 55 next (clockwise)
        // 60 - minute gives us: 0->0, 55->5, 50->10...
        // Wait, the numbers on face are 0,55,50,45... going clockwise
        // So position for "55" label is at 30° (one tick clockwise from top)
        // Position for "0" label is at 0° (top)
        if minute == 0 {
            return 0
        }
        return Double(60 - minute) * 6  // 6 degrees per minute
    }

    private func handleDrag(value: DragGesture.Value, center: CGPoint, radius: CGFloat) {
        isDragging = true
        stopTimer()

        let vector = CGVector(
            dx: value.location.x - center.x,
            dy: value.location.y - center.y
        )

        // Calculate angle from top (0°), going clockwise
        var angle = atan2(vector.dx, -vector.dy) * 180 / .pi
        if angle < 0 { angle += 360 }

        // Convert angle to minutes (0° = 0 min, 360° = 60 min)
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
            clockwise: false
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
