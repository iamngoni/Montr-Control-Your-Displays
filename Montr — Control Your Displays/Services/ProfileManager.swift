import Combine
import Foundation
import IOKit.ps

/// Manages display profiles
@MainActor
final class ProfileManager: ObservableObject, @unchecked Sendable {
    // MARK: - Published Properties

    @Published private(set) var profiles: [Profile] = []
    @Published private(set) var activeProfile: Profile?
    @Published var autoActivationEnabled: Bool = true

    // MARK: - Private Properties

    private var powerSourceObserver: Any?
    private var autoActivationTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Singleton

    @MainActor static let shared = ProfileManager()

    private init() {
        loadProfiles()
        setupObservers()
        setupPowerSourceObserver()
        startAutoActivationTimer()
    }

    // MARK: - Public Methods

    /// Create a new profile from current display settings
    func createProfile(name: String) async -> Profile {
        let displays = DisplayManager.shared.displays
        let brightnessController = BrightnessController.shared
        let colorTempController = ColorTemperatureController.shared

        var displaySettings: [DisplaySettings] = []

        for display in displays {
            let settings = DisplaySettings(
                displayId: display.stableIdentifier,
                brightness: brightnessController.getBrightness(for: display),
                contrast: brightnessController.getContrast(for: display),
                colorTemperature: colorTempController.getTemperature(for: display),
                nightShiftEnabled: colorTempController.isEnabled
            )
            displaySettings.append(settings)
        }

        let profile = Profile(
            name: name,
            displaySettings: displaySettings,
            quickDimEnabled: brightnessController.quickDimEnabled
        )

        profiles.append(profile)
        saveProfiles()

        return profile
    }

    /// Update an existing profile with current settings
    func updateProfile(_ profile: Profile) async {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }

        var updatedProfile = profile
        updatedProfile.modifiedAt = Date()

        let displays = DisplayManager.shared.displays
        let brightnessController = BrightnessController.shared
        let colorTempController = ColorTemperatureController.shared

        for display in displays {
            let settings = DisplaySettings(
                displayId: display.stableIdentifier,
                brightness: brightnessController.getBrightness(for: display),
                contrast: brightnessController.getContrast(for: display),
                colorTemperature: colorTempController.getTemperature(for: display),
                nightShiftEnabled: colorTempController.isEnabled
            )
            updatedProfile.updateSettings(settings)
        }

        updatedProfile.quickDimEnabled = brightnessController.quickDimEnabled

        profiles[index] = updatedProfile
        saveProfiles()
    }

    /// Delete a profile
    func deleteProfile(_ profile: Profile) {
        profiles.removeAll { $0.id == profile.id }
        if activeProfile?.id == profile.id {
            activeProfile = nil
        }
        saveProfiles()
    }

    /// Rename a profile
    func renameProfile(_ profile: Profile, to newName: String) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index].name = newName
        profiles[index].modifiedAt = Date()
        saveProfiles()
    }

    /// Apply a profile
    func applyProfile(_ profile: Profile) async {
        let displays = DisplayManager.shared.displays
        let brightnessController = BrightnessController.shared
        let colorTempController = ColorTemperatureController.shared

        // If profile has no display settings yet, capture current settings first
        if profile.displaySettings.isEmpty && !displays.isEmpty {
            await updateProfile(profile)
            // After updating, the profile now has settings, so just mark it active
            activeProfile = profiles.first { $0.id == profile.id }
            SettingsManager.shared.activeProfileId = profile.id.uuidString
            return
        }

        for display in displays {
            if let settings = profile.settings(for: display.stableIdentifier) {
                await brightnessController.setBrightness(for: display, value: settings.brightness)

                if let contrast = settings.contrast {
                    await brightnessController.setContrast(for: display, value: contrast)
                }

                await colorTempController.setTemperature(
                    for: display, kelvin: settings.colorTemperature)

                if settings.nightShiftEnabled {
                    await colorTempController.enable()
                } else {
                    await colorTempController.disable()
                }
            }
        }

        // Handle quick dim
        if profile.quickDimEnabled != brightnessController.quickDimEnabled {
            await brightnessController.toggleQuickDim()
        }

        activeProfile = profile
        SettingsManager.shared.activeProfileId = profile.id.uuidString
    }

    /// Add an auto-activation trigger to a profile
    func addTrigger(to profile: Profile, trigger: AutoActivationTrigger) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index].triggers.append(trigger)
        profiles[index].modifiedAt = Date()
        saveProfiles()
    }

    /// Remove an auto-activation trigger from a profile
    func removeTrigger(from profile: Profile, triggerId: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index].triggers.removeAll { $0.id == triggerId }
        profiles[index].modifiedAt = Date()
        saveProfiles()
    }

    /// Export profiles to JSON data
    func exportProfiles() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(profiles)
    }

    /// Import profiles from JSON data
    func importProfiles(from data: Data) -> Bool {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let importedProfiles = try? decoder.decode([Profile].self, from: data) else {
            return false
        }

        // Merge with existing profiles (avoid duplicates by ID)
        for imported in importedProfiles {
            if !profiles.contains(where: { $0.id == imported.id }) {
                profiles.append(imported)
            }
        }

        saveProfiles()
        return true
    }

    // MARK: - Private Methods

    private func loadProfiles() {
        profiles = SettingsManager.shared.profiles

        // Create default profiles if none exist
        if profiles.isEmpty {
            profiles = Profile.defaultProfiles
            saveProfiles()
        }

        // Restore active profile
        if let activeId = SettingsManager.shared.activeProfileId,
            let uuid = UUID(uuidString: activeId),
            let profile = profiles.first(where: { $0.id == uuid })
        {
            activeProfile = profile
        }
    }

    private func saveProfiles() {
        SettingsManager.shared.profiles = profiles
    }

    private func setupObservers() {
        // Listen for display changes
        NotificationCenter.default.publisher(for: .displaysDidChange)
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.checkAutoActivation()
                }
            }
            .store(in: &cancellables)
    }

    private func setupPowerSourceObserver() {
        // Monitor power source changes
        let loop = CFRunLoopGetCurrent()
        let context = Unmanaged.passUnretained(self).toOpaque()

        if let source = IOPSNotificationCreateRunLoopSource(
            { context in
                guard let context = context else { return }
                let manager = Unmanaged<ProfileManager>.fromOpaque(context).takeUnretainedValue()
                Task { @MainActor in
                    await manager.checkAutoActivation()
                }
            }, context)
        {
            CFRunLoopAddSource(loop, source.takeRetainedValue(), .commonModes)
        }
    }

    private func startAutoActivationTimer() {
        // Check auto-activation every minute for time-based triggers
        autoActivationTimer?.invalidate()
        autoActivationTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                await self?.checkAutoActivation()
            }
        }
    }

    private func checkAutoActivation() async {
        guard autoActivationEnabled else { return }

        let connectedDisplayIds = DisplayManager.shared.connectedDisplayIds
        let currentTime = Date()
        let isOnBattery = isRunningOnBattery()

        for profile in profiles {
            if profile.shouldActivate(
                connectedDisplayIds: connectedDisplayIds,
                currentTime: currentTime,
                isOnBattery: isOnBattery
            ) {
                // Don't re-apply if already active
                if activeProfile?.id != profile.id {
                    await applyProfile(profile)
                    return
                }
            }
        }
    }

    private func isRunningOnBattery() -> Bool {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as [CFTypeRef]

        for source in sources {
            if let description = IOPSGetPowerSourceDescription(snapshot, source)?
                .takeUnretainedValue() as? [String: Any]
            {
                if let type = description[kIOPSTypeKey] as? String,
                    type == kIOPSInternalBatteryType
                {
                    if let powerSource = description[kIOPSPowerSourceStateKey] as? String {
                        return powerSource == kIOPSBatteryPowerValue
                    }
                }
            }
        }

        return false
    }
}
