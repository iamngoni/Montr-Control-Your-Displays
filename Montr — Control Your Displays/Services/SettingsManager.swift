import Foundation

/// Central manager for app settings and persistence
final class SettingsManager {
    // MARK: - Keys

    private enum Keys {
        static let launchAtLogin = "launchAtLogin"
        static let restoreOnQuit = "restoreOnQuit"
        static let quickDimPercentage = "quickDimPercentage"
        static let displayCustomNames = "displayCustomNames"
        static let perDisplayBrightness = "perDisplayBrightness"
        static let perDisplayContrast = "perDisplayContrast"
        static let nightShiftEnabled = "nightShiftEnabled"
        static let nightShiftTemperature = "nightShiftTemperature"
        static let perDisplayTemperature = "perDisplayTemperature"
        static let nightShiftSchedule = "nightShiftSchedule"
        static let profiles = "profiles"
        static let activeProfileId = "activeProfileId"
        static let hotkeys = "hotkeys"
        static let contrastEnabled = "contrastEnabled"
        static let originalDisplaySettings = "originalDisplaySettings"
        static let sentryEnabled = "sentryEnabled"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

    // MARK: - Singleton

    static let shared = SettingsManager()

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        registerDefaults()
    }

    // MARK: - Default Values

    private func registerDefaults() {
        defaults.register(defaults: [
            Keys.launchAtLogin: false,
            Keys.restoreOnQuit: true,
            Keys.quickDimPercentage: 20,
            Keys.nightShiftEnabled: false,
            Keys.nightShiftTemperature: 6500,
            Keys.contrastEnabled: false,
            Keys.sentryEnabled: true,
            Keys.hasCompletedOnboarding: false
        ])
    }

    // MARK: - General Settings

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Keys.launchAtLogin) }
        set { defaults.set(newValue, forKey: Keys.launchAtLogin) }
    }

    var restoreOnQuit: Bool {
        get { defaults.bool(forKey: Keys.restoreOnQuit) }
        set { defaults.set(newValue, forKey: Keys.restoreOnQuit) }
    }

    var quickDimPercentage: Int {
        get { defaults.integer(forKey: Keys.quickDimPercentage) }
        set { defaults.set(newValue, forKey: Keys.quickDimPercentage) }
    }

    var contrastEnabled: Bool {
        get { defaults.bool(forKey: Keys.contrastEnabled) }
        set { defaults.set(newValue, forKey: Keys.contrastEnabled) }
    }

    var sentryEnabled: Bool {
        get { defaults.bool(forKey: Keys.sentryEnabled) }
        set { defaults.set(newValue, forKey: Keys.sentryEnabled) }
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Keys.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: Keys.hasCompletedOnboarding) }
    }

    // MARK: - Display Names

    var displayCustomNames: [String: String] {
        get {
            defaults.dictionary(forKey: Keys.displayCustomNames) as? [String: String] ?? [:]
        }
        set {
            defaults.set(newValue, forKey: Keys.displayCustomNames)
        }
    }

    func customName(for displayId: String) -> String? {
        displayCustomNames[displayId]
    }

    func setCustomName(_ name: String?, for displayId: String) {
        var names = displayCustomNames
        names[displayId] = name
        displayCustomNames = names
    }

    // MARK: - Brightness

    var savedBrightness: [String: Int] {
        get {
            defaults.dictionary(forKey: Keys.perDisplayBrightness) as? [String: Int] ?? [:]
        }
        set {
            defaults.set(newValue, forKey: Keys.perDisplayBrightness)
        }
    }

    func saveBrightness(_ brightness: Int, for displayId: String) {
        var saved = savedBrightness
        saved[displayId] = brightness
        savedBrightness = saved
    }

    func savedBrightness(for displayId: String) -> Int? {
        savedBrightness[displayId]
    }

    // MARK: - Contrast

    var savedContrast: [String: Int] {
        get {
            defaults.dictionary(forKey: Keys.perDisplayContrast) as? [String: Int] ?? [:]
        }
        set {
            defaults.set(newValue, forKey: Keys.perDisplayContrast)
        }
    }

    func saveContrast(_ contrast: Int, for displayId: String) {
        var saved = savedContrast
        saved[displayId] = contrast
        savedContrast = saved
    }

    // MARK: - Night Shift

    var nightShiftEnabled: Bool {
        get { defaults.bool(forKey: Keys.nightShiftEnabled) }
        set { defaults.set(newValue, forKey: Keys.nightShiftEnabled) }
    }

    var nightShiftTemperature: Int {
        get { defaults.integer(forKey: Keys.nightShiftTemperature) }
        set { defaults.set(newValue, forKey: Keys.nightShiftTemperature) }
    }

    var perDisplayTemperature: [String: Int] {
        get {
            defaults.dictionary(forKey: Keys.perDisplayTemperature) as? [String: Int] ?? [:]
        }
        set {
            defaults.set(newValue, forKey: Keys.perDisplayTemperature)
        }
    }

    var nightShiftSchedule: NightShiftSchedule {
        get {
            guard let data = defaults.data(forKey: Keys.nightShiftSchedule),
                  let schedule = try? decoder.decode(NightShiftSchedule.self, from: data) else {
                return .default
            }
            return schedule
        }
        set {
            if let data = try? encoder.encode(newValue) {
                defaults.set(data, forKey: Keys.nightShiftSchedule)
            }
        }
    }

    // MARK: - Profiles

    var profiles: [Profile] {
        get {
            guard let data = defaults.data(forKey: Keys.profiles),
                  let profiles = try? decoder.decode([Profile].self, from: data) else {
                return []
            }
            return profiles
        }
        set {
            if let data = try? encoder.encode(newValue) {
                defaults.set(data, forKey: Keys.profiles)
            }
        }
    }

    var activeProfileId: String? {
        get { defaults.string(forKey: Keys.activeProfileId) }
        set { defaults.set(newValue, forKey: Keys.activeProfileId) }
    }

    // MARK: - Hotkeys

    var hotkeys: [HotkeyManager.HotkeyAction: HotkeyManager.Hotkey]? {
        get {
            guard let data = defaults.data(forKey: Keys.hotkeys),
                  let hotkeys = try? decoder.decode([HotkeyManager.HotkeyAction: HotkeyManager.Hotkey].self, from: data) else {
                return nil
            }
            return hotkeys
        }
        set {
            if let value = newValue,
               let data = try? encoder.encode(value) {
                defaults.set(data, forKey: Keys.hotkeys)
            } else {
                defaults.removeObject(forKey: Keys.hotkeys)
            }
        }
    }

    // MARK: - Original Display Settings

    var originalDisplaySettings: [OriginalDisplaySettings] {
        get {
            guard let data = defaults.data(forKey: Keys.originalDisplaySettings),
                  let settings = try? decoder.decode([OriginalDisplaySettings].self, from: data) else {
                return []
            }
            return settings
        }
        set {
            if let data = try? encoder.encode(newValue) {
                defaults.set(data, forKey: Keys.originalDisplaySettings)
            }
        }
    }

    func saveOriginalSettings(_ settings: OriginalDisplaySettings) {
        var allSettings = originalDisplaySettings
        allSettings.removeAll { $0.displayId == settings.displayId }
        allSettings.append(settings)
        originalDisplaySettings = allSettings
    }

    func originalSettings(for displayId: String) -> OriginalDisplaySettings? {
        originalDisplaySettings.first { $0.displayId == displayId }
    }

    // MARK: - Reset

    func resetAllSettings() {
        let domain = Bundle.main.bundleIdentifier!
        defaults.removePersistentDomain(forName: domain)
        defaults.synchronize()
        registerDefaults()
    }
}
