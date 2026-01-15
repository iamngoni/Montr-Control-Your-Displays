import Combine
import CoreGraphics
import ServiceManagement
import Sparkle
import SwiftUI

// MARK: - Settings Theme

private enum SettingsTheme {
    static let background = Color(red: 0.043, green: 0.051, blue: 0.067)  // #0b0d11
    static let cardBackground = Color(red: 0.067, green: 0.075, blue: 0.094)  // #111318
    static let inputBackground = Color(red: 0.20, green: 0.21, blue: 0.23)
    static let teal = Color(red: 0.0, green: 0.78, blue: 0.73)
    static let textPrimary = Color.white
    static let textSecondary = Color(white: 0.55)
    static let divider = Color(white: 0.25)
    static let iconBackground = Color(red: 0.22, green: 0.23, blue: 0.25)
}

// MARK: - Settings Tab

enum SettingsTab: String, CaseIterable {
    case general = "General"
    case displays = "Displays"
    case nightShift = "Night Shift"
    case profiles = "Profiles"
    case shortcuts = "Shortcuts"
    case advanced = "Advanced"

    var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .displays: return "display"
        case .nightShift: return "moon.fill"
        case .profiles: return "square.on.square"
        case .shortcuts: return "keyboard"
        case .advanced: return "wrench.and.screwdriver"
        }
    }
}

// MARK: - Main Settings View

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            SettingsTabBar(selectedTab: $selectedTab)
                .padding(.top, 16)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

            // Divider between tab bar and content
            Rectangle()
                .fill(SettingsTheme.divider)
                .frame(height: 1)

            // Content
            ScrollView {
                Group {
                    switch selectedTab {
                    case .general:
                        GeneralSettingsView()
                    case .displays:
                        DisplaysSettingsView()
                    case .nightShift:
                        NightShiftSettingsView()
                    case .profiles:
                        ProfilesSettingsView()
                    case .shortcuts:
                        ShortcutsSettingsView()
                    case .advanced:
                        AdvancedSettingsView()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 20)
            }
        }
        .frame(width: 560, height: 480)
        .background(SettingsTheme.background)
    }
}

// MARK: - Settings Tab Bar

private struct SettingsTabBar: View {
    @Binding var selectedTab: SettingsTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                SettingsTabButton(
                    tab: tab,
                    isSelected: selectedTab == tab
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedTab = tab
                    }
                }
            }

            Spacer()
        }
    }
}

private struct SettingsTabButton: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    if isSelected || isHovering {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                isSelected
                                    ? SettingsTheme.teal
                                    : SettingsTheme.cardBackground
                            )
                            .frame(width: 48, height: 40)
                    }

                    Image(systemName: tab.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(isSelected ? .black : SettingsTheme.textSecondary)
                }
                .frame(width: 48, height: 40)

                Text(tab.rawValue)
                    .font(.system(size: 10))
                    .foregroundColor(isSelected ? SettingsTheme.teal : SettingsTheme.textSecondary)
            }
            .frame(width: 70)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Sparkle Updater

final class SparkleUpdater: ObservableObject {
    private let updaterController: SPUStandardUpdaterController

    @Published var canCheckForUpdates = false

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
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
        VStack(spacing: 14) {
            // Grouped: Launch at login + Restore display settings
            VStack(spacing: 0) {
                // Launch at login
                SettingsRowContent(
                    icon: "power",
                    iconColor: SettingsTheme.teal
                ) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Launch at login")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(SettingsTheme.textPrimary)
                            Text("Start Montr when you log in")
                                .font(.system(size: 11))
                                .foregroundColor(SettingsTheme.textSecondary)
                        }
                        Spacer()
                        Toggle("", isOn: $launchAtLogin)
                            .toggleStyle(TealToggleStyle())
                            .labelsHidden()
                    }
                }
                .onChange(of: launchAtLogin) { _, newValue in
                    SettingsManager.shared.launchAtLogin = newValue
                    setLaunchAtLogin(newValue)
                }

                // Divider
                Rectangle()
                    .fill(SettingsTheme.divider)
                    .frame(height: 1)

                // Restore display settings
                SettingsRowContent(
                    icon: "arrow.counterclockwise",
                    iconColor: SettingsTheme.teal
                ) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Restore display settings on quit")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(SettingsTheme.textPrimary)
                            Text("Reset brightness when closing app")
                                .font(.system(size: 11))
                                .foregroundColor(SettingsTheme.textSecondary)
                        }
                        Spacer()
                        Toggle("", isOn: $restoreOnQuit)
                            .toggleStyle(TealToggleStyle())
                            .labelsHidden()
                    }
                }
                .onChange(of: restoreOnQuit) { _, newValue in
                    SettingsManager.shared.restoreOnQuit = newValue
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(SettingsTheme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(SettingsTheme.divider, lineWidth: 1)
            )

            // Quick Dim card
            SettingsCard(icon: "sparkles", iconColor: SettingsTheme.teal, title: "Quick Dim") {
                HStack(spacing: 16) {
                    Text("Quick dim level:")
                        .font(.system(size: 12))
                        .foregroundColor(SettingsTheme.textSecondary)
                        .fixedSize()

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Track background
                            Capsule()
                                .fill(SettingsTheme.inputBackground)
                                .frame(height: 8)

                            // Filled track
                            Capsule()
                                .fill(SettingsTheme.teal)
                                .frame(
                                    width: max(8, geometry.size.width * (quickDimPercentage / 50)),
                                    height: 8)
                        }
                        .frame(height: 24)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { gesture in
                                    let newValue = min(
                                        max(5, gesture.location.x / geometry.size.width * 50), 50)
                                    quickDimPercentage = round(newValue / 5) * 5
                                }
                        )
                    }
                    .frame(height: 24)

                    Text("\(Int(quickDimPercentage))%")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(SettingsTheme.textPrimary)
                        .frame(width: 40, alignment: .trailing)
                }
            }
            .onChange(of: quickDimPercentage) { _, newValue in
                SettingsManager.shared.quickDimPercentage = Int(newValue)
            }

            // Privacy card
            SettingsCard(icon: "gearshape.fill", iconColor: SettingsTheme.teal, title: "Privacy") {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Send crash reports (Sentry)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(SettingsTheme.textPrimary)
                        Text("Crash reports help us improve Montr. No personal data is collected.")
                            .font(.system(size: 11))
                            .foregroundColor(SettingsTheme.textSecondary)
                    }
                    Spacer()
                    Toggle("", isOn: $sentryEnabled)
                        .toggleStyle(TealToggleStyle())
                        .labelsHidden()
                }
            }
            .onChange(of: sentryEnabled) { _, newValue in
                SettingsManager.shared.sentryEnabled = newValue
            }

            // Check for updates
            HStack {
                Button {
                    sparkleUpdater.checkForUpdates()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 12))
                            .foregroundColor(SettingsTheme.teal)
                        Text("Check for Updates...")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(SettingsTheme.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(SettingsTheme.cardBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(SettingsTheme.divider, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!sparkleUpdater.canCheckForUpdates)

                Spacer()

                Text(
                    "Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")"
                )
                .font(.system(size: 12))
                .foregroundColor(SettingsTheme.textSecondary)
                .italic()
            }
            .padding(.top, 8)
        }
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

    private var primaryDisplayId: CGDirectDisplayID {
        CGMainDisplayID()
    }

    var body: some View {
        VStack(spacing: 12) {
            // Header row
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(SettingsTheme.iconBackground)
                        .frame(width: 32, height: 32)

                    Image(systemName: "display.2")
                        .font(.system(size: 13))
                        .foregroundColor(SettingsTheme.teal)
                }

                Text("Connected Displays")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(SettingsTheme.textPrimary)

                Spacer()

                Text(
                    "\(displayManager.displays.count) display\(displayManager.displays.count == 1 ? "" : "s")"
                )
                .font(.system(size: 12))
                .foregroundColor(SettingsTheme.textSecondary)
            }
            .padding(.horizontal, 4)

            // Display list card
            VStack(spacing: 0) {
                if displayManager.displays.isEmpty {
                    HStack {
                        Image(systemName: "display.trianglebadge.exclamationmark")
                            .font(.system(size: 14))
                            .foregroundColor(SettingsTheme.textSecondary)

                        Text("No displays connected")
                            .font(.system(size: 12))
                            .foregroundColor(SettingsTheme.textSecondary)

                        Spacer()
                    }
                    .padding(16)
                } else {
                    ForEach(Array(displayManager.displays.enumerated()), id: \.element.id) {
                        index, display in
                        DisplayListRow(
                            display: display,
                            isPrimary: display.id == primaryDisplayId,
                            onRename: {
                                customName = display.customName ?? ""
                                editingDisplay = display
                            }
                        )

                        if index < displayManager.displays.count - 1 {
                            Rectangle()
                                .fill(SettingsTheme.divider)
                                .frame(height: 1)
                        }
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(SettingsTheme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(SettingsTheme.divider, lineWidth: 1)
            )

            // Refresh button
            Button {
                Task {
                    await displayManager.refreshDisplays()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                    Text("Refresh Displays")
                        .font(.system(size: 12))
                }
                .foregroundColor(SettingsTheme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(SettingsTheme.divider, lineWidth: 1)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.clear)
                        )
                )
            }
            .buttonStyle(.plain)
        }
        .alert(
            "Rename Display",
            isPresented: Binding(
                get: { editingDisplay != nil },
                set: { if !$0 { editingDisplay = nil } }
            )
        ) {
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

private struct DisplayListRow: View {
    let display: Display
    let isPrimary: Bool
    let onRename: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Display icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(SettingsTheme.inputBackground)
                    .frame(width: 40, height: 40)

                Image(systemName: "display")
                    .font(.system(size: 15))
                    .foregroundColor(SettingsTheme.textSecondary)
            }

            // Display info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(display.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(SettingsTheme.textPrimary)

                    if isPrimary {
                        Text("PRIMARY")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(SettingsTheme.teal)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(SettingsTheme.teal.opacity(0.2))
                            )
                    }
                }

                Text(display.modelName)
                    .font(.system(size: 11))
                    .foregroundColor(SettingsTheme.textSecondary)
            }

            Spacer()

            // DDC/CI badge
            Text(display.controlMethodBadge)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(SettingsTheme.teal)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(SettingsTheme.teal.opacity(0.15))
                )

            // Rename button
            Button(action: onRename) {
                Text("Rename")
                    .font(.system(size: 11))
                    .foregroundColor(SettingsTheme.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
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
        VStack(spacing: 12) {
            // Schedule card
            SettingsCard(icon: "clock", iconColor: SettingsTheme.teal, title: "Schedule") {
                VStack(spacing: 12) {
                    // Mode dropdown row
                    HStack {
                        Text("Mode")
                            .font(.system(size: 12))
                            .foregroundColor(SettingsTheme.textSecondary)

                        Spacer()

                        Menu {
                            ForEach(NightShiftSchedule.ScheduleMode.allCases, id: \.self) { mode in
                                Button(mode.displayName) {
                                    schedule.mode = mode
                                    saveSchedule()
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(schedule.mode.displayName)
                                    .font(.system(size: 12))
                                    .foregroundColor(SettingsTheme.textPrimary)

                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10))
                                    .foregroundColor(SettingsTheme.textSecondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(SettingsTheme.inputBackground)
                            )
                        }
                        .menuStyle(.borderlessButton)
                    }

                    // Custom time pickers (shown when mode is custom)
                    if schedule.mode == .custom {
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Start")
                                    .font(.system(size: 10))
                                    .foregroundColor(SettingsTheme.textSecondary)

                                Picker(
                                    "",
                                    selection: Binding(
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
                                    )
                                ) {
                                    ForEach(0..<24) { hour in
                                        Text(String(format: "%02d:00", hour)).tag(hour)
                                    }
                                }
                                .frame(width: 90)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("End")
                                    .font(.system(size: 10))
                                    .foregroundColor(SettingsTheme.textSecondary)

                                Picker(
                                    "",
                                    selection: Binding(
                                        get: { schedule.customTimeRange?.end.hour ?? 7 },
                                        set: { hour in
                                            schedule.customTimeRange?.end.hour = hour
                                            saveSchedule()
                                        }
                                    )
                                ) {
                                    ForEach(0..<24) { hour in
                                        Text(String(format: "%02d:00", hour)).tag(hour)
                                    }
                                }
                                .frame(width: 90)
                            }

                            Spacer()
                        }
                    }
                }
            }

            // Transition card with gradient slider
            SettingsCard(icon: "sparkles", iconColor: .orange, title: "Transition") {
                HStack(spacing: 12) {
                    Text("Transition duration:")
                        .font(.system(size: 12))
                        .foregroundColor(SettingsTheme.textSecondary)

                    // Custom gradient slider
                    GeometryReader { geometry in
                        let normalizedValue = (Double(schedule.transitionDuration) - 1) / 119

                        ZStack(alignment: .leading) {
                            // Track background
                            Capsule()
                                .fill(SettingsTheme.inputBackground)
                                .frame(height: 6)

                            // Gradient fill
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [.orange, .yellow],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(
                                    width: max(6, geometry.size.width * normalizedValue), height: 6)

                            // Thumb
                            Circle()
                                .fill(.white)
                                .frame(width: 14, height: 14)
                                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                                .offset(
                                    x: max(
                                        0,
                                        min(
                                            geometry.size.width - 14,
                                            (geometry.size.width - 14) * normalizedValue)))
                        }
                        .frame(height: 20)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { gesture in
                                    let normalized = min(
                                        max(0, gesture.location.x / geometry.size.width), 1)
                                    schedule.transitionDuration = Int(1 + normalized * 119)
                                }
                                .onEnded { _ in
                                    saveSchedule()
                                }
                        )
                    }
                    .frame(height: 20)

                    Text("\(schedule.transitionDuration) min")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(SettingsTheme.textPrimary)
                        .frame(width: 50, alignment: .trailing)
                }
            }

            // Display Mode card
            SettingsCard(icon: "display", iconColor: SettingsTheme.teal, title: "Display Mode") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Apply to all displays")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(SettingsTheme.textPrimary)

                        Text("When disabled, each display can have its own color temperature.")
                            .font(.system(size: 11))
                            .foregroundColor(SettingsTheme.textSecondary)
                    }

                    Spacer()

                    Toggle("", isOn: $schedule.applyToAllDisplays)
                        .toggleStyle(TealToggleStyle())
                        .labelsHidden()
                }
            }
            .onChange(of: schedule.applyToAllDisplays) { _, _ in
                saveSchedule()
            }
        }
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
    @State private var showingAddTrigger = false

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            // Left side - Profile list (no card background)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(profileManager.profiles) { profile in
                    ProfileListRow(
                        profile: profile,
                        isSelected: selectedProfile?.id == profile.id,
                        isActive: profileManager.activeProfile?.id == profile.id
                    ) {
                        selectedProfile = profile
                    }
                }

                Spacer()
            }
            .frame(width: 110)

            // Right side - Profile details
            if let profile = selectedProfile {
                ProfileDetailPanel(
                    profile: profile,
                    onAddTrigger: { showingAddTrigger = true }
                )
            } else {
                VStack {
                    Spacer()
                    Text("Select a profile")
                        .font(.system(size: 12))
                        .foregroundColor(SettingsTheme.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            if selectedProfile == nil {
                selectedProfile = profileManager.profiles.first
            }
        }
        .onChange(of: profileManager.profiles) { _, newProfiles in
            if let selected = selectedProfile {
                selectedProfile = newProfiles.first { $0.id == selected.id }
            }
        }
        .sheet(isPresented: $showingAddTrigger) {
            if let profile = selectedProfile {
                AddTriggerSheet(profile: profile)
            }
        }
    }
}

private struct ProfileListRow: View {
    let profile: Profile
    let isSelected: Bool
    let isActive: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(profile.name)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundColor(isSelected ? .black : SettingsTheme.textPrimary)
                    .lineLimit(1)

                Spacer()

                if isActive && !isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(SettingsTheme.teal)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        isSelected
                            ? SettingsTheme.teal
                            : (isHovering ? SettingsTheme.cardBackground : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

private struct ProfileDetailPanel: View {
    let profile: Profile
    let onAddTrigger: () -> Void

    @StateObject private var profileManager = ProfileManager.shared
    @State private var name: String
    @State private var autoActivationEnabled: Bool

    init(profile: Profile, onAddTrigger: @escaping () -> Void) {
        self.profile = profile
        self.onAddTrigger = onAddTrigger
        _name = State(initialValue: profile.name)
        _autoActivationEnabled = State(initialValue: true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // NAME label and field
            VStack(alignment: .leading, spacing: 8) {
                Text("NAME")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(SettingsTheme.textSecondary)
                    .tracking(0.5)

                TextField("", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(SettingsTheme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(SettingsTheme.cardBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(SettingsTheme.divider, lineWidth: 1)
                    )
                    .onSubmit {
                        profileManager.renameProfile(profile, to: name)
                    }
            }

            // Auto-Activation row with icon
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(SettingsTheme.iconBackground)
                        .frame(width: 32, height: 32)

                    Image(systemName: "clock")
                        .font(.system(size: 13))
                        .foregroundColor(SettingsTheme.textSecondary)
                }

                Text("Auto-Activation")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(SettingsTheme.textPrimary)

                Spacer()

                Toggle("", isOn: $autoActivationEnabled)
                    .toggleStyle(TealToggleStyle())
                    .labelsHidden()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(SettingsTheme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(SettingsTheme.divider, lineWidth: 1)
            )

            // Triggers card (shown when auto-activation is enabled)
            if autoActivationEnabled {
                VStack(spacing: 0) {
                    // Existing triggers
                    ForEach(profile.triggers) { trigger in
                        TriggerRow(trigger: trigger) {
                            profileManager.removeTrigger(from: profile, triggerId: trigger.id)
                        }

                        if trigger.id != profile.triggers.last?.id {
                            Rectangle()
                                .fill(SettingsTheme.divider)
                                .frame(height: 1)
                        }
                    }

                    // Add Trigger button
                    Button(action: onAddTrigger) {
                        Text("Add Trigger...")
                            .font(.system(size: 12))
                            .foregroundColor(SettingsTheme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(SettingsTheme.divider, lineWidth: 1)
                    )
                    .padding(.top, profile.triggers.isEmpty ? 0 : 8)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(SettingsTheme.cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(SettingsTheme.divider, lineWidth: 1)
                )
            }

            Spacer()

            // Action buttons
            VStack(spacing: 10) {
                // Apply Profile - teal filled button
                Button {
                    Task {
                        await profileManager.applyProfile(profile)
                    }
                } label: {
                    Text("Apply Profile")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(SettingsTheme.teal)
                        )
                }
                .buttonStyle(.plain)

                // Update with Current Settings - outlined button
                Button {
                    Task {
                        await profileManager.updateProfile(profile)
                    }
                } label: {
                    Text("Update with Current Settings")
                        .font(.system(size: 12))
                        .foregroundColor(SettingsTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(SettingsTheme.divider, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .onChange(of: profile.id) { _, _ in
            name = profile.name
            autoActivationEnabled = true
        }
    }
}

private struct TriggerRow: View {
    let trigger: AutoActivationTrigger
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock")
                .font(.system(size: 12))
                .foregroundColor(SettingsTheme.textSecondary)

            Text(descriptionForTrigger)
                .font(.system(size: 12))
                .foregroundColor(SettingsTheme.textPrimary)

            Spacer()

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(SettingsTheme.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
    }

    private var descriptionForTrigger: String {
        switch trigger.type {
        case .connectedDisplays:
            if let displays = trigger.requiredDisplayIds, !displays.isEmpty {
                return "When \(displays.count) display(s) connected"
            }
            return "When specific displays connected"
        case .timeOfDay:
            if let range = trigger.timeRange {
                return
                    "Between \(String(format: "%d:00", range.start.hour)) and \(String(format: "%d:00", range.end.hour))"
            }
            return "Time of day"
        case .powerSource:
            return trigger.requiresBattery == true ? "When on battery" : "When plugged in"
        }
    }
}

// MARK: - Add Trigger Sheet

private struct AddTriggerSheet: View {
    let profile: Profile

    @Environment(\.dismiss) private var dismiss
    @StateObject private var profileManager = ProfileManager.shared
    @StateObject private var displayManager = DisplayManager.shared

    @State private var selectedType: AutoActivationTrigger.TriggerType = .timeOfDay
    @State private var startHour = 22
    @State private var endHour = 7
    @State private var requiresBattery = true
    @State private var selectedDisplayIds: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .foregroundColor(SettingsTheme.textSecondary)

                Spacer()

                Text("Add Trigger")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(SettingsTheme.textPrimary)

                Spacer()

                Button("Add") {
                    addTrigger()
                    dismiss()
                }
                .foregroundColor(SettingsTheme.teal)
            }
            .padding()

            Divider()
                .background(SettingsTheme.divider)

            VStack(alignment: .leading, spacing: 16) {
                // Trigger type
                VStack(alignment: .leading, spacing: 6) {
                    Text("Trigger Type")
                        .font(.system(size: 11))
                        .foregroundColor(SettingsTheme.textSecondary)

                    Picker("", selection: $selectedType) {
                        Text("Time").tag(AutoActivationTrigger.TriggerType.timeOfDay)
                        Text("Power").tag(AutoActivationTrigger.TriggerType.powerSource)
                        Text("Displays").tag(AutoActivationTrigger.TriggerType.connectedDisplays)
                    }
                    .pickerStyle(.segmented)
                }

                // Type-specific options
                switch selectedType {
                case .timeOfDay:
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Start")
                                .font(.system(size: 10))
                                .foregroundColor(SettingsTheme.textSecondary)
                            Picker("", selection: $startHour) {
                                ForEach(0..<24) { hour in
                                    Text(String(format: "%02d:00", hour)).tag(hour)
                                }
                            }
                            .frame(width: 90)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("End")
                                .font(.system(size: 10))
                                .foregroundColor(SettingsTheme.textSecondary)
                            Picker("", selection: $endHour) {
                                ForEach(0..<24) { hour in
                                    Text(String(format: "%02d:00", hour)).tag(hour)
                                }
                            }
                            .frame(width: 90)
                        }
                    }

                case .powerSource:
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Activate when")
                            .font(.system(size: 11))
                            .foregroundColor(SettingsTheme.textSecondary)

                        Picker("", selection: $requiresBattery) {
                            Text("On Battery").tag(true)
                            Text("Plugged In").tag(false)
                        }
                        .pickerStyle(.segmented)
                    }

                case .connectedDisplays:
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Required displays")
                            .font(.system(size: 11))
                            .foregroundColor(SettingsTheme.textSecondary)

                        if displayManager.displays.isEmpty {
                            Text("No displays connected")
                                .font(.system(size: 11))
                                .foregroundColor(SettingsTheme.textSecondary)
                        } else {
                            ForEach(displayManager.displays) { display in
                                HStack {
                                    Image(
                                        systemName: selectedDisplayIds.contains(
                                            display.stableIdentifier)
                                            ? "checkmark.square.fill" : "square"
                                    )
                                    .foregroundColor(
                                        selectedDisplayIds.contains(display.stableIdentifier)
                                            ? SettingsTheme.teal : SettingsTheme.textSecondary)
                                    Text(display.displayName)
                                        .font(.system(size: 11))
                                        .foregroundColor(SettingsTheme.textPrimary)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if selectedDisplayIds.contains(display.stableIdentifier) {
                                        selectedDisplayIds.remove(display.stableIdentifier)
                                    } else {
                                        selectedDisplayIds.insert(display.stableIdentifier)
                                    }
                                }
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding()
        }
        .frame(width: 320, height: 280)
        .background(SettingsTheme.background)
    }

    private func addTrigger() {
        let trigger: AutoActivationTrigger

        switch selectedType {
        case .timeOfDay:
            trigger = AutoActivationTrigger(
                type: .timeOfDay,
                timeRange: TimeRange(
                    start: TimeOfDay(hour: startHour, minute: 0),
                    end: TimeOfDay(hour: endHour, minute: 0)
                )
            )
        case .powerSource:
            trigger = AutoActivationTrigger(
                type: .powerSource,
                requiresBattery: requiresBattery
            )
        case .connectedDisplays:
            trigger = AutoActivationTrigger(
                type: .connectedDisplays,
                requiredDisplayIds: selectedDisplayIds
            )
        }

        profileManager.addTrigger(to: profile, trigger: trigger)
    }
}

// MARK: - Shortcuts Settings

struct ShortcutsSettingsView: View {
    @StateObject private var hotkeyManager = HotkeyManager.shared

    var body: some View {
        VStack(spacing: 12) {
            SettingsCard(icon: "command", iconColor: SettingsTheme.teal, title: "Global Shortcuts")
            {
                VStack(spacing: 8) {
                    ForEach(HotkeyManager.HotkeyAction.allCases, id: \.self) { action in
                        HStack {
                            Text(action.rawValue)
                                .font(.system(size: 12))
                                .foregroundColor(SettingsTheme.textPrimary)

                            Spacer()

                            if let hotkey = hotkeyManager.registeredHotkeys[action] {
                                Text(hotkey.displayString)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(SettingsTheme.textPrimary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(SettingsTheme.inputBackground)
                                    )
                            } else {
                                Text("Not set")
                                    .font(.system(size: 10))
                                    .foregroundColor(SettingsTheme.textSecondary)
                            }
                        }
                    }
                }
            }

            SettingsCard(icon: "hand.raised", iconColor: SettingsTheme.teal, title: "Permissions") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Global shortcuts require Accessibility permission")
                        .font(.system(size: 11))
                        .foregroundColor(SettingsTheme.textSecondary)

                    Button {
                        NSWorkspace.shared.open(
                            URL(
                                string:
                                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                            )!)
                    } label: {
                        Text("Open Accessibility Settings")
                            .font(.system(size: 11))
                            .foregroundColor(SettingsTheme.teal)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Button {
                    hotkeyManager.resetToDefaults()
                } label: {
                    Text("Reset to Defaults")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(SettingsTheme.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(SettingsTheme.cardBackground)
                        )
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
    }
}

// MARK: - Advanced Settings

struct AdvancedSettingsView: View {
    @State private var contrastEnabled = SettingsManager.shared.contrastEnabled

    var body: some View {
        VStack(spacing: 12) {
            SettingsRow(icon: "slider.horizontal.below.rectangle", iconColor: SettingsTheme.teal) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable contrast control")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(SettingsTheme.textPrimary)
                        Text("Shows contrast slider for DDC/CI displays")
                            .font(.system(size: 11))
                            .foregroundColor(SettingsTheme.textSecondary)
                    }
                    Spacer()
                    Toggle("", isOn: $contrastEnabled)
                        .toggleStyle(TealToggleStyle())
                        .labelsHidden()
                }
            }
            .onChange(of: contrastEnabled) { _, newValue in
                SettingsManager.shared.contrastEnabled = newValue
            }

            SettingsCard(icon: "ladybug", iconColor: SettingsTheme.teal, title: "Debug") {
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        Task {
                            await DisplayManager.shared.refreshDisplays()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10))
                            Text("Refresh Displays")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(SettingsTheme.teal)
                    }
                    .buttonStyle(.plain)

                    Button {
                        SettingsManager.shared.resetAllSettings()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                            Text("Reset All Settings")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }

            SettingsCard(icon: "info.circle", iconColor: SettingsTheme.teal, title: "About") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Montr")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(SettingsTheme.textPrimary)
                        Spacer()
                        Text(
                            "Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")"
                        )
                        .font(.system(size: 11))
                        .foregroundColor(SettingsTheme.textSecondary)
                    }

                    Divider()
                        .background(SettingsTheme.divider)

                    Link(destination: URL(string: "https://montr.iamngoni.dev")!) {
                        HStack(spacing: 6) {
                            Image(systemName: "link")
                                .font(.system(size: 10))
                            Text("Website")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(SettingsTheme.teal)
                    }

                    Link(destination: URL(string: "mailto:ngmangudya@codecraftsolutions.co.za")!) {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.bubble")
                                .font(.system(size: 10))
                            Text("Report an Issue")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(SettingsTheme.teal)
                    }
                }
            }
        }
    }
}

// MARK: - Reusable Components

private struct SettingsRow<Content: View>: View {
    let icon: String
    var iconColor: Color = SettingsTheme.teal
    var badge: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 14) {
            // Icon with background
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(SettingsTheme.iconBackground)
                    .frame(width: 40, height: 40)

                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(iconColor)
            }
            .overlay(alignment: .topLeading) {
                if let badge = badge {
                    Text(badge)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(SettingsTheme.textPrimary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(SettingsTheme.cardBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(SettingsTheme.divider, lineWidth: 1)
                                )
                        )
                        .offset(x: -12, y: -6)
                }
            }

            content
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(SettingsTheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(SettingsTheme.divider, lineWidth: 1)
        )
    }
}

// Row content without background - for use in grouped cards with dividers
private struct SettingsRowContent<Content: View>: View {
    let icon: String
    var iconColor: Color = SettingsTheme.teal
    var badge: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 14) {
            // Icon with background
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(SettingsTheme.iconBackground)
                    .frame(width: 40, height: 40)

                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(iconColor)
            }
            .overlay(alignment: .topLeading) {
                if let badge = badge {
                    Text(badge)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(SettingsTheme.textPrimary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(SettingsTheme.cardBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(SettingsTheme.divider, lineWidth: 1)
                                )
                        )
                        .offset(x: -12, y: -6)
                }
            }

            content
        }
        .padding(14)
    }
}

private struct SettingsCard<Content: View>: View {
    let icon: String
    var iconColor: Color = SettingsTheme.teal
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(SettingsTheme.iconBackground)
                        .frame(width: 36, height: 36)

                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(iconColor)
                }

                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(SettingsTheme.textPrimary)
            }

            // Content
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(SettingsTheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(SettingsTheme.divider, lineWidth: 1)
        )
    }
}

// MARK: - Teal Toggle Style

private struct TealToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label

            ZStack {
                Capsule()
                    .fill(configuration.isOn ? SettingsTheme.teal : SettingsTheme.inputBackground)
                    .frame(width: 44, height: 24)

                Circle()
                    .fill(.white)
                    .frame(width: 20, height: 20)
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                    .offset(x: configuration.isOn ? 10 : -10)
            }
            .onTapGesture {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    configuration.isOn.toggle()
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
}
