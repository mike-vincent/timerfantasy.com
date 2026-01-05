import SwiftUI

enum AppearanceMode: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct ContentView: View {
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "timer")
                }
                .tag(0)

            SettingsView(appearanceMode: $appearanceMode)
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(1)
        }
        .preferredColorScheme(appearanceMode.colorScheme)
    }
}

struct HomeView: View {
    @State private var timers: [TimerItem] = [TimerItem()]
    @State private var selectedTimerID: UUID?

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTimerID) {
                Section {
                    ForEach($timers) { $timer in
                        NavigationLink(value: timer.id) {
                            HStack {
                                Circle()
                                    .fill(timer.remainingSeconds > 0 ? Color.red.opacity(0.85) : Color.gray.opacity(0.3))
                                    .frame(width: 12, height: 12)
                                Text(timer.label.isEmpty ? "Timer" : timer.label)
                                Spacer()
                                if timer.remainingSeconds > 0 {
                                    Text(formatTime(timer.remainingSeconds))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .onDelete(perform: deleteTimer)
                } header: {
                    Text("Timers")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .textCase(nil)
                }

                Button(action: addTimer) {
                    Label("Add Timer", systemImage: "plus.circle")
                }
            }
            .navigationTitle("")
            #if os(macOS)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            #endif
        } detail: {
            if let selectedID = selectedTimerID,
               let index = timers.firstIndex(where: { $0.id == selectedID }) {
                TimerDetailView(timer: $timers[index])
            } else {
                Text("Select a timer")
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            if selectedTimerID == nil, let first = timers.first {
                selectedTimerID = first.id
            }
        }
    }

    private func addTimer() {
        let newTimer = TimerItem()
        timers.append(newTimer)
        selectedTimerID = newTimer.id
    }

    private func deleteTimer(at offsets: IndexSet) {
        timers.remove(atOffsets: offsets)
        if timers.isEmpty {
            addTimer()
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

struct SettingsView: View {
    @Binding var appearanceMode: AppearanceMode

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appearanceMode) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .textCase(nil)
            } footer: {
                Text("Choose how the app appears on your device.")
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct TimerDetailView: View {
    @Binding var timer: TimerItem

    var body: some View {
        VStack(spacing: 20) {
            TextField("Timer name", text: $timer.label)
                .textFieldStyle(.plain)
                .font(.title2)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)

            TimerView(timerItem: $timer)
                .frame(width: 280, height: 280)

            Text(formatTime(timer.remainingSeconds))
                .font(.system(size: 48, weight: .bold, design: .monospaced))
                .foregroundColor(timer.remainingSeconds > 0 ? .primary : .secondary)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
