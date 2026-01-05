import SwiftUI
import AVFoundation

struct TimerView: View {
    @Binding var timerItem: TimerItem
    @State private var timer: Timer?
    @State private var isDragging = false

    private let maxTimeOptions: [Int] = [10, 20, 30, 60, 90, 120, 180, 240]

    private var tickMarks: [Int] {
        let interval = Int(timerItem.maxMinutes) / 12
        return (0..<12).map { $0 * interval }
    }

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let radius = size / 2 - 20

            ZStack {
                // Background circle (white)
                Circle()
                    .fill(Color.white)
                    .frame(width: size - 40, height: size - 40)

                // Red pie (remaining time)
                if timerItem.remainingSeconds > 0 {
                    let angle = (timerItem.remainingSeconds / (timerItem.maxMinutes * 60)) * 360
                    PieSlice(
                        startAngle: .degrees(-90),
                        endAngle: .degrees(-90 - angle),
                        clockwise: true
                    )
                    .fill(Color.red.opacity(0.85))
                    .frame(width: size - 44, height: size - 44)
                }

                // Small minute tick marks
                ForEach(0..<Int(timerItem.maxMinutes), id: \.self) { minute in
                    let angle = -(Double(minute) / timerItem.maxMinutes) * 360
                    Rectangle()
                        .fill(Color.gray.opacity(0.5))
                        .frame(width: 1, height: 5)
                        .offset(y: -radius + 2.5)
                        .rotationEffect(.degrees(angle))
                }

                // Major tick marks and numbers
                ForEach(tickMarks, id: \.self) { minute in
                    let angle = angleForMinute(minute)
                    let numberRadius = radius - 25
                    let isMajor = minute % Int(timerItem.maxMinutes / 4) == 0

                    Rectangle()
                        .fill(Color.gray)
                        .frame(width: 2, height: isMajor ? 15 : 8)
                        .offset(y: -radius + (isMajor ? 7.5 : 4))
                        .rotationEffect(.degrees(angle))

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

                // Max time picker
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Menu {
                            ForEach(maxTimeOptions, id: \.self) { minutes in
                                Button("\(minutes)m") {
                                    resetTimer()
                                    timerItem.maxMinutes = Double(minutes)
                                }
                            }
                        } label: {
                            Text("\(Int(timerItem.maxMinutes))m")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.gray)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.8))
                                .cornerRadius(4)
                        }
                        .menuStyle(.borderlessButton)
                    }
                }
                .padding(6)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleDrag(value: value, center: center, radius: radius)
                    }
                    .onEnded { _ in
                        isDragging = false
                        if timerItem.totalSeconds > 0 && !timerItem.isRunning {
                            startTimer()
                        }
                    }
            )
            .onTapGesture(count: 2) {
                resetTimer()
            }
        }
    }

    private func angleForMinute(_ minute: Int) -> Double {
        return -(Double(minute) / timerItem.maxMinutes) * 360
    }

    private func handleDrag(value: DragGesture.Value, center: CGPoint, radius: CGFloat) {
        isDragging = true
        stopTimer()

        let vector = CGVector(
            dx: value.location.x - center.x,
            dy: value.location.y - center.y
        )

        var angle = atan2(vector.dx, -vector.dy) * 180 / .pi
        if angle > 0 { angle = angle - 360 }
        let ccwAngle = -angle

        let minutes = ccwAngle / 360 * timerItem.maxMinutes
        let seconds = minutes * 60
        let snappedSeconds = (seconds / 30).rounded() * 30

        timerItem.totalSeconds = min(snappedSeconds, timerItem.maxMinutes * 60)
        timerItem.remainingSeconds = min(snappedSeconds, timerItem.maxMinutes * 60)
    }

    private func startTimer() {
        timerItem.isRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if timerItem.remainingSeconds > 0 {
                timerItem.remainingSeconds -= 0.1
            } else {
                timerItem.remainingSeconds = 0
                stopTimer()
                playCompletionSound()
            }
        }
    }

    private func stopTimer() {
        timerItem.isRunning = false
        timer?.invalidate()
        timer = nil
    }

    private func resetTimer() {
        stopTimer()
        timerItem.totalSeconds = 0
        timerItem.remainingSeconds = 0
    }

    private func playCompletionSound() {
        #if os(macOS)
        NSSound.beep()
        #else
        AudioServicesPlaySystemSound(1005) // System sound for iOS
        #endif
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
    struct PreviewWrapper: View {
        @State var item = TimerItem()
        var body: some View {
            TimerView(timerItem: $item)
                .frame(width: 300, height: 300)
                .padding()
        }
    }
    return PreviewWrapper()
}
