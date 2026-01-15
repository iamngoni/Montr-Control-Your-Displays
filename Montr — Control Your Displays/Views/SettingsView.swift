import SwiftUI
import ServiceManagement
import Sparkle

/// Main settings window view
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            DisplaysSettingsView()
                .tabItem {
                    Label("Displays", systemImage: "display")
                }

            NightShiftSettingsView()
                .tabItem {
                    Label("Night Shift", systemImage: "moon.fill")
                }

            ProfilesSettingsView()
                .tabItem {
                    Label("Profiles", systemImage: "square.stack")
                }

            ShortcutsSettingsView()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }

            AdvancedSettingsView()
                .tabItem {
                    Label("Advanced", systemImage: "wrench.and.screwdriver")
                }
        }
        .frame(width: 500, height: 400)
    }
}

// MARK: - Sparkle Updater

/// Wrapper class for Sparkle's SPUStandardUpdaterController to use in SwiftUI
final class SparkleUpdater: ObservableObject {
    private let updaterController: SPUStandardUpdaterController

    @Published var canCheckForUpdates = false

    init() {
        // Initialize Sparkle updater
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        // Observe canCheckForUpdates
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @StateObject private var sparkleUpdater = SparkleUpdater()
    @State private var launchAtLogin = SettingsManager.shared.launchAtLogin
    @State private var restoreOnQuit = SettingsManager.shared.restoreOnQuit
    @State private var quickDimPercentage = Double(SettingsManager.shared.quickDimPercentage)
    @State private var sentryEnabled = SettingsManager.shared.sentryEnabled

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        SettingsManager.shared.launchAtLogin = newValue
                        setLaunchAtLogin(newValue)
                    }

                Toggle("Restore display settings on quit", isOn: $restoreOnQuit)
                    .onChange(of: restoreOnQuit) { _, newValue in
                        SettingsManager.shared.restoreOnQuit = newValue
                    }
            }

            Section("Quick Dim") {
                HStack {
                    Text("Quick dim level:")
                    Slider(value: $quickDimPercentage, in: 5...50, step: 5)
                    Text("\(Int(quickDimPercentage))%")
                        .frame(width: 40)
                }
                .onChange(of: quickDimPercentage) { _, newValue in
                    SettingsManager.shared.quickDimPercentage = Int(newValue)
                }
            }

            Section("Privacy") {
                Toggle("Send crash reports (Sentry)", isOn: $sentryEnabled)
                    .onChange(of: sentryEnabled) { _, newValue in
                        SettingsManager.shared.sentryEnabled = newValue
                    }

                Text("Crash reports help us improve Montr. No personal data is collected.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                HStack {
                    Button("Check for Updates...") {
                        sparkleUpdater.checkForUpdates()
                    }
                    .disabled(!sparkleUpdater.canCheckForUpdates)

                    Spacer()

                    Text("Version 1.0.0")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to set launch at login: \(error)")
        }
    }
}

// MARK: - Displays Settings

struct DisplaysSettingsView: View {
    @StateObject private var displayManager = DisplayManager.shared
    @State private var editingDisplay: Display?
    @State private var customName = ""

    var body: some View {
        Form {
            Section("Connected Displays") {
                ForEach(displayManager.displays) { display in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(display.displayName)
                                .fontWeight(.medium)

                            Text(display.modelName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        DisplayBadge(text: display.controlMethodBadge)

                        Button("Rename") {
                            customName = display.customName ?? ""
                            editingDisplay = display
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert("Rename Display", isPresented: Binding(
            get: { editingDisplay != nil },
            set: { if !$0 { editingDisplay = nil } }
        )) {
            TextField("Display Name", text: $customName)
            Button("Cancel", role: .cancel) {
                editingDisplay = nil
            }
            Button("Save") {
                if let display = editingDisplay {
                    SettingsManager.shared.setCustomName(
                        customName.isEmpty ? nil : customName,
                        for: String(display.id)
                    )
                    Task {
                        await displayManager.refreshDisplays()
                    }
                }
                editingDisplay = nil
            }
        }
    }
}

// MARK: - Night Shift Settings

struct NightShiftSettingsView: View {
    @StateObject private var colorTempController = ColorTemperatureController.shared
    @State private var schedule: NightShiftSchedule

    init() {
        _schedule = State(initialValue: SettingsManager.shared.nightShiftSchedule)
    }

    var body: some View {
        Form {
            Section("Schedule") {
                Picker("Mode", selection: $schedule.mode) {
                    ForEach(NightShiftSchedule.ScheduleMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .onChange(of: schedule.mode) { _, _ in
                    saveSchedule()
                }

                if schedule.mode == .custom {
                    HStack {
                        Text("Start:")
                        Picker("", selection: Binding(
                            get: { schedule.customTimeRange?.start.hour ?? 22 },
                            set: { hour in
                                if schedule.customTimeRange == nil {
                                    schedule.customTimeRange = TimeRange(
                                        start: TimeOfDay(hour: hour, minute: 0),
                                        end: TimeOfDay(hour: 7, minute: 0)
                                    )
                                } else {
                                    schedule.customTimeRange?.start.hour = hour
                                }
                                saveSchedule()
                            }
                        )) {
                            ForEach(0..<24) { hour in
                                Text(String(format: "%02d:00", hour)).tag(hour)
                            }
                        }
                        .frame(width: 80)
                    }

                    HStack {
                        Text("End:")
                        Picker("", selection: Binding(
                            get: { schedule.customTimeRange?.end.hour ?? 7 },
                            set: { hour in
                                schedule.customTimeRange?.end.hour = hour
                                saveSchedule()
                            }
                        )) {
                            ForEach(0..<24) { hour in
                                Text(String(format: "%02d:00", hour)).tag(hour)
                            }
                        }
                        .frame(width: 80)
                    }
                }
            }

            Section("Transition") {
                HStack {
                    Text("Transition duration:")
                    Slider(
                        value: Binding(
                            get: { Double(schedule.transitionDuration) },
                            set: { schedule.transitionDuration = Int($0); saveSchedule() }
                        ),
                        in: 1...120,
                        step: 1
                    )
                    Text("\(schedule.transitionDuration) min")
                        .frame(width: 60)
                }
            }

            Section("Display Mode") {
                Toggle("Apply to all displays", isOn: $schedule.applyToAllDisplays)
                    .onChange(of: schedule.applyToAllDisplays) { _, _ in
                        saveSchedule()
                    }

                Text("When disabled, each display can have its own color temperature.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func saveSchedule() {
        SettingsManager.shared.nightShiftSchedule = schedule
        colorTempController.schedule = schedule
    }
}

// MARK: - Profiles Settings

struct ProfilesSettingsView: View {
    @StateObject private var profileManager = ProfileManager.shared
    @State private var selectedProfile: Profile?
    @State private var showingDeleteConfirmation = false

    var body: some View {
        HSplitView {
            // Profile list
            List(profileManager.profiles, selection: $selectedProfile) { profile in
                HStack {
                    Text(profile.name)
                    Spacer()
                    if profileManager.activeProfile?.id == profile.id {
                        Image(systemName: "checkmark")
                            .foregroundColor(.accentColor)
                    }
                }
                .tag(profile)
            }
            .frame(minWidth: 150)

            // Profile details
            if let profile = selectedProfile {
                ProfileDetailView(profile: profile)
            } else {
                Text("Select a profile")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task {
                        let newProfile = await profileManager.createProfile(name: "New Profile")
                        selectedProfile = newProfile
                    }
                } label: {
                    Image(systemName: "plus")
                }

                Button {
                    showingDeleteConfirmation = true
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(selectedProfile == nil)
            }
        }
        .alert("Delete Profile?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let profile = selectedProfile {
                    profileManager.deleteProfile(profile)
                    selectedProfile = nil
                }
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }
}

// MARK: - Profile Detail View

struct ProfileDetailView: View {
    let profile: Profile

    @StateObject private var profileManager = ProfileManager.shared
    @State private var name: String
    @State private var autoActivationEnabled = true

    init(profile: Profile) {
        self.profile = profile
        _name = State(initialValue: profile.name)
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                    .onSubmit {
                        profileManager.renameProfile(profile, to: name)
                    }
            }

            Section("Auto-Activation") {
                Toggle("Enable auto-activation", isOn: $autoActivationEnabled)

                ForEach(profile.triggers) { trigger in
                    HStack {
                        Image(systemName: iconForTrigger(trigger))
                        Text(descriptionForTrigger(trigger))
                        Spacer()
                        Button(role: .destructive) {
                            profileManager.removeTrigger(from: profile, triggerId: trigger.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button("Add Trigger...") {
                    // Show trigger picker
                }
            }

            Section {
                Button("Apply Profile") {
                    Task {
                        await profileManager.applyProfile(profile)
                    }
                }

                Button("Update with Current Settings") {
                    Task {
                        await profileManager.updateProfile(profile)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func iconForTrigger(_ trigger: AutoActivationTrigger) -> String {
        switch trigger.type {
        case .connectedDisplays: return "display"
        case .timeOfDay: return "clock"
        case .powerSource: return "battery.100"
        }
    }

    private func descriptionForTrigger(_ trigger: AutoActivationTrigger) -> String {
        switch trigger.type {
        case .connectedDisplays:
            return "When specific displays connected"
        case .timeOfDay:
            if let range = trigger.timeRange {
                return "Between \(range.start.hour):00 and \(range.end.hour):00"
            }
            return "Time of day"
        case .powerSource:
            return trigger.requiresBattery == true ? "When on battery" : "When plugged in"
        }
    }
}

// MARK: - Shortcuts Settings

struct ShortcutsSettingsView: View {
    @StateObject private var hotkeyManager = HotkeyManager.shared

    var body: some View {
        Form {
            Section("Global Shortcuts") {
                ForEach(HotkeyManager.HotkeyAction.allCases, id: \.self) { action in
                    HStack {
                        Text(action.rawValue)
                        Spacer()
                        if let hotkey = hotkeyManager.registeredHotkeys[action] {
                            Text(hotkey.displayString)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.2))
                                .cornerRadius(4)
                        } else {
                            Text("Not set")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Section {
                Button("Reset to Defaults") {
                    hotkeyManager.resetToDefaults()
                }
            }

            Section {
                Text("Note: Global shortcuts require Accessibility permission.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("Open Accessibility Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Advanced Settings

struct AdvancedSettingsView: View {
    @State private var contrastEnabled = SettingsManager.shared.contrastEnabled

    var body: some View {
        Form {
            Section("Display Controls") {
                Toggle("Enable contrast control", isOn: $contrastEnabled)
                    .onChange(of: contrastEnabled) { _, newValue in
                        SettingsManager.shared.contrastEnabled = newValue
                    }

                Text("Shows contrast slider for DDC/CI compatible displays.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Debug") {
                Button("Refresh Displays") {
                    Task {
                        await DisplayManager.shared.refreshDisplays()
                    }
                }

                Button("Reset All Settings") {
                    SettingsManager.shared.resetAllSettings()
                }
                .foregroundColor(.red)
            }

            Section("About") {
                HStack {
                    Text("Montr")
                    Spacer()
                    Text("Version 1.0.0")
                        .foregroundColor(.secondary)
                }

                Link("GitHub Repository", destination: URL(string: "https://github.com/montr/montr")!)
                Link("Report an Issue", destination: URL(string: "https://github.com/montr/montr/issues")!)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
}
