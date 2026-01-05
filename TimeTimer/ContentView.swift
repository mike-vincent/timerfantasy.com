import SwiftUI

struct ContentView: View {
    @State private var timers: [TimerItem] = [
        TimerItem(),
        TimerItem(),
        TimerItem()
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ForEach($timers) { $timer in
                    HStack {
                        TimerView(timerItem: $timer)
                            .frame(width: 200, height: 200)

                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Label", text: $timer.label)
                                .textFieldStyle(.plain)
                                .font(.headline)

                            Text(formatTime(timer.remainingSeconds))
                                .font(.system(size: 32, weight: .bold, design: .monospaced))
                                .foregroundColor(timer.remainingSeconds > 0 ? .primary : .secondary)
                        }
                        .frame(width: 120)

                        Spacer()
                    }
                    .padding()
                    .background(Color(white: 0.98))
                    .cornerRadius(12)
                }

                Button(action: addTimer) {
                    Label("Add Timer", systemImage: "plus.circle")
                }
                .padding()
            }
            .padding()
        }
        .frame(minWidth: 400, minHeight: 500)
    }

    private func addTimer() {
        timers.append(TimerItem())
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

struct TimerItem: Identifiable {
    let id = UUID()
    var label: String = ""
    var totalSeconds: Double = 0
    var remainingSeconds: Double = 0
    var maxMinutes: Double = 60
    var isRunning: Bool = false
}

#Preview {
    ContentView()
}
