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
    @StateObject private var store = TimerStore()

    var body: some View {
        TimerListDetailView(timers: $store.timers, store: store)
            .preferredColorScheme(appearanceMode.colorScheme)
    }
}

struct HomeTabView: View {
    @ObservedObject var store: TimerStore
    var searchText: String

    var body: some View {
        MyTimersView(store: store, searchText: searchText)
    }
}

struct TimersTabView: View {
    @ObservedObject var store: TimerStore
    var searchText: String

    var body: some View {
        MyTimersView(store: store, searchText: searchText)
    }
}


struct MyTimersView: View {
    @ObservedObject var store: TimerStore
    var searchText: String

    var body: some View {
        TimerListDetailView(timers: $store.timers, store: store, searchText: searchText)
    }
}

struct SettingsTabView: View {
    @Binding var appearanceMode: AppearanceMode
    var store: TimerStore

    var body: some View {
        SettingsView(appearanceMode: $appearanceMode, store: store)
    }
}

struct SettingsView: View {
    @Binding var appearanceMode: AppearanceMode
    var store: TimerStore
    @State private var showClearConfirm = false

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

            Section {
                Button(action: { showClearConfirm = true }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Clear All Timers")
                    }
                    .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            } header: {
                Text("Data")
                    .textCase(nil)
            } footer: {
                Text("Remove all saved timers and reset to default.")
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .confirmationDialog("Clear All Timers?", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("Clear All", role: .destructive) {
                clearAllTimers()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all your timers. This action cannot be undone.")
        }
    }

    private func clearAllTimers() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
        #endif
        // Stop all running timers first to prevent crash
        for i in store.timers.indices {
            store.timers[i].isRunning = false
        }
        // Small delay to let onDisappear trigger
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            store.timers.removeAll()
            store.timerCounter = 0
            let newTimer = TimerItem(label: "Timer A", color: TimerColor.forIndex(0))
            store.timers.append(newTimer)
            store.timerCounter = 1
            store.saveToCloud()
        }
    }
}

struct SearchTabView: View {
    @ObservedObject var store: TimerStore
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            SearchResultsView(searchText: searchText, store: store)
                .navigationTitle("Search")
        }
        .searchable(text: $searchText, placement: .automatic, prompt: "Search timers")
    }
}

struct SearchResultsView: View {
    let searchText: String
    @ObservedObject var store: TimerStore
    @State private var resetTimerID: UUID?

    var filteredTimers: [TimerItem] {
        store.timers.filter { $0.label.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if filteredTimers.isEmpty {
                    Text("No timers found")
                        .foregroundColor(.secondary)
                        .padding(.top, 40)
                } else {
                    ForEach(filteredTimers) { timer in
                        if let index = store.timers.firstIndex(where: { $0.id == timer.id }) {
                            TimerCard(timer: $store.timers[index], store: store, clockSize: 100, fontSize: 32, showResetConfirm: Binding(
                                get: { resetTimerID == timer.id },
                                set: { if $0 { resetTimerID = timer.id } }
                            ), onResetTap: { resetTimerID = timer.id })
                        }
                    }
                }
            }
            .padding(20)
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog("Reset Timer?", isPresented: Binding(
            get: { resetTimerID != nil },
            set: { if !$0 { resetTimerID = nil } }
        ), titleVisibility: .visible) {
            Button("Reset", role: .destructive) {
                if let id = resetTimerID,
                   let index = store.timers.firstIndex(where: { $0.id == id }) {
                    #if os(macOS)
                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
                    #endif
                    store.timers[index].totalSeconds = 0
                    store.timers[index].remainingSeconds = 0
                    store.timers[index].isRunning = false
                    store.saveToCloud()
                }
                resetTimerID = nil
            }
            Button("Cancel", role: .cancel) { resetTimerID = nil }
        } message: {
            Text("This will reset the current timer.")
        }
    }
}

struct SingleTimerDetailView: View {
    @Binding var timer: TimerItem
    var store: TimerStore
    @State private var showResetConfirm = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                TimerCard(timer: $timer, store: store, clockSize: 120, fontSize: 36, showResetConfirm: $showResetConfirm, onResetTap: { showResetConfirm = true })
            }
            .padding(20)
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog("Reset Timer?", isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button("Reset", role: .destructive) {
                #if os(macOS)
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
                #endif
                timer.totalSeconds = 0
                timer.remainingSeconds = 0
                timer.isRunning = false
                store.saveToCloud()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will reset the current timer.")
        }
    }
}

struct TimerListDetailView: View {
    @Binding var timers: [TimerItem]
    var store: TimerStore
    var searchText: String = ""
    @State private var resetTimerID: UUID?

    var filteredIndices: [Int] {
        timers.indices.filter { index in
            searchText.isEmpty || timers[index].label.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(filteredIndices, id: \.self) { index in
                    TimerCard(timer: $timers[index], store: store, clockSize: 100, fontSize: 32, showResetConfirm: Binding(
                        get: { resetTimerID == timers[index].id },
                        set: { if $0 { resetTimerID = timers[index].id } }
                    ), onResetTap: { resetTimerID = timers[index].id })
                }
            }
            .padding(20)
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog("Reset Timer?", isPresented: Binding(
            get: { resetTimerID != nil },
            set: { if !$0 { resetTimerID = nil } }
        ), titleVisibility: .visible) {
            Button("Reset", role: .destructive) {
                if let id = resetTimerID,
                   let index = timers.firstIndex(where: { $0.id == id }) {
                    #if os(macOS)
                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
                    #endif
                    timers[index].totalSeconds = 0
                    timers[index].remainingSeconds = 0
                    timers[index].isRunning = false
                    store.saveToCloud()
                }
                resetTimerID = nil
            }
            Button("Cancel", role: .cancel) { resetTimerID = nil }
        } message: {
            Text("This will reset the current timer.")
        }
    }
}

struct TimerCard: View {
    @Binding var timer: TimerItem
    var store: TimerStore
    var clockSize: CGFloat
    var fontSize: CGFloat
    @Binding var showResetConfirm: Bool
    var onResetTap: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top row with corner icons
            HStack {
                Image(systemName: "archivebox.fill")
                    .font(.body)
                    .foregroundColor(.gray.opacity(0.5))
                    .padding(8)
                    .glassEffect()
                Spacer()
                Image(systemName: "archivebox.fill")
                    .font(.body)
                    .foregroundColor(.gray.opacity(0.5))
                    .padding(8)
                    .glassEffect()
            }

            // Timer name row
            HStack(spacing: 8) {
                Circle()
                    .fill(timer.timerColor.color)
                    .frame(width: 12, height: 12)
                TextField("Timer name", text: $timer.label)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .onChange(of: timer.label) { _, _ in store.saveToCloud() }
                Spacer()
            }

            HStack(spacing: 20) {
                TimerView(timerItem: $timer)
                    .frame(width: clockSize, height: clockSize)
                    .onChange(of: timer.totalSeconds) { _, _ in store.saveToCloud() }
                    .onChange(of: timer.maxMinutes) { _, _ in store.saveToCloud() }

                Spacer()

                Text(formatTime(timer.remainingSeconds))
                    .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                    .foregroundColor(timer.remainingSeconds > 0 ? .primary : .secondary)
            }

            // Controls row
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                    Text("\(Int(timer.maxMinutes))m")
                }
                .font(.body)
                .foregroundColor(timer.totalSeconds > 0 ? .primary : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(12)
                .fixedSize()

                Spacer()

                Button(action: { timer.isRunning = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                        Text("Start")
                    }
                    .font(.body)
                    .foregroundColor(timer.isRunning || timer.totalSeconds == 0 ? .secondary : .primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(12)
                    .fixedSize()
                }
                .buttonStyle(.plain)
                .disabled(timer.isRunning || timer.totalSeconds == 0)

                Button(action: { timer.isRunning = false }) {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill")
                        Text("Stop")
                    }
                    .font(.body)
                    .foregroundColor(!timer.isRunning ? .secondary : .primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(12)
                    .fixedSize()
                }
                .buttonStyle(.plain)
                .disabled(!timer.isRunning)

                Button(action: { onResetTap?() ?? (showResetConfirm = true) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset")
                    }
                    .font(.body)
                    .foregroundColor(timer.totalSeconds == 0 ? .secondary : .primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(12)
                    .fixedSize()
                }
                .buttonStyle(.plain)
                .disabled(timer.totalSeconds == 0)
            }

            // Bottom row with corner icons
            HStack {
                Image(systemName: "archivebox.fill")
                    .font(.body)
                    .foregroundColor(.gray.opacity(0.5))
                    .padding(8)
                    .glassEffect()
                Spacer()
                Image(systemName: "archivebox.fill")
                    .font(.body)
                    .foregroundColor(.gray.opacity(0.5))
                    .padding(8)
                    .glassEffect()
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func formatTimeEditable(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    private func parseTime(_ string: String) -> Double? {
        let parts = string.split(separator: ":")
        if parts.count == 2,
           let mins = Int(parts[0]),
           let secs = Int(parts[1]) {
            return Double(mins * 60 + secs)
        } else if let totalSeconds = Int(string) {
            return Double(totalSeconds)
        }
        return nil
    }
}

struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.8))
            .cornerRadius(12)
    }
}

enum TimerColor: String, Codable, CaseIterable {
    case red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink

    var color: Color {
        switch self {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .mint: return .mint
        case .teal: return .teal
        case .cyan: return .cyan
        case .blue: return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .pink: return .pink
        }
    }

    static func forIndex(_ index: Int) -> TimerColor {
        let cases = TimerColor.allCases
        return cases[index % cases.count]
    }
}

struct TimerItem: Identifiable, Codable {
    var id = UUID()
    var label: String = ""
    var totalSeconds: Double = 0
    var remainingSeconds: Double = 0
    var maxMinutes: Double = 60
    var isRunning: Bool = false
    var timerColor: TimerColor = .red

    init(id: UUID = UUID(), label: String = "", color: TimerColor = .red) {
        self.id = id
        self.label = label
        self.timerColor = color
    }
}

class TimerStore: ObservableObject {
    @Published var timers: [TimerItem] = []
    @Published var timerCounter: Int = 0

    private let key = "savedTimers"
    private let counterKey = "timerCounter"
    private let cloudStore = NSUbiquitousKeyValueStore.default
    private let localDefaults = UserDefaults.standard

    init() {
        load()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cloudDataChanged),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloudStore
        )

        cloudStore.synchronize()
    }

    @objc private func cloudDataChanged(_ notification: Notification) {
        DispatchQueue.main.async {
            self.load()
        }
    }

    private func load() {
        // Try iCloud first, fall back to local
        if let data = cloudStore.data(forKey: key),
           let decoded = try? JSONDecoder().decode([TimerItem].self, from: data) {
            timers = decoded
        } else if let data = localDefaults.data(forKey: key),
                  let decoded = try? JSONDecoder().decode([TimerItem].self, from: data) {
            timers = decoded
        }

        let cloudCounter = cloudStore.longLong(forKey: counterKey)
        let localCounter = localDefaults.integer(forKey: counterKey)
        timerCounter = max(Int(cloudCounter), localCounter)

        if timers.isEmpty {
            let initial = TimerItem(label: "Timer A", color: TimerColor.forIndex(0))
            timers = [initial]
            timerCounter = 1
            save()
        }
    }

    func saveToCloud() {
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(timers) {
            cloudStore.set(data, forKey: key)
            localDefaults.set(data, forKey: key)
        }
        cloudStore.set(Int64(timerCounter), forKey: counterKey)
        localDefaults.set(timerCounter, forKey: counterKey)
        cloudStore.synchronize()
    }

    func nextAvailableLetter() -> (letter: String, index: Int) {
        let usedLabels = Set(timers.map { $0.label })
        for i in 0..<26 {
            let letter = String(Character(UnicodeScalar(65 + i)!))
            let label = "Timer \(letter)"
            if !usedLabels.contains(label) {
                return (letter, i)
            }
        }
        // Fallback if all A-Z used
        return (String(timerCounter), timerCounter)
    }

    func addTimer() -> UUID {
        let (letter, index) = nextAvailableLetter()
        let newTimer = TimerItem(label: "Timer \(letter)", color: TimerColor.forIndex(index))
        timers.append(newTimer)
        save()
        return newTimer.id
    }

    func deleteTimer(at offsets: IndexSet) -> UUID? {
        timers.remove(atOffsets: offsets)
        if timers.isEmpty {
            let newTimer = TimerItem(label: "Timer A", color: TimerColor.forIndex(0))
            timers.append(newTimer)
            save()
            return newTimer.id
        }
        save()
        return nil
    }
}

#Preview {
    ContentView()
}
