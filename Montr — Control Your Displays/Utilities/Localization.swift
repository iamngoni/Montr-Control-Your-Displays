import Foundation

/// Localization utilities
enum L10n {
    // MARK: - General

    static let appName = NSLocalizedString("app.name", value: "Montr", comment: "App name")
    static let settings = NSLocalizedString("general.settings", value: "Settings", comment: "Settings")
    static let quit = NSLocalizedString("general.quit", value: "Quit", comment: "Quit")
    static let cancel = NSLocalizedString("general.cancel", value: "Cancel", comment: "Cancel")
    static let save = NSLocalizedString("general.save", value: "Save", comment: "Save")
    static let delete = NSLocalizedString("general.delete", value: "Delete", comment: "Delete")
    static let create = NSLocalizedString("general.create", value: "Create", comment: "Create")

    // MARK: - Displays

    static let displays = NSLocalizedString("displays.title", value: "Displays", comment: "Displays section title")
    static let noDisplays = NSLocalizedString("displays.none", value: "No displays detected", comment: "No displays message")
    static let builtInDisplay = NSLocalizedString("displays.builtin", value: "Built-in Display", comment: "Built-in display name")
    static let brightness = NSLocalizedString("displays.brightness", value: "Brightness", comment: "Brightness label")
    static let contrast = NSLocalizedString("displays.contrast", value: "Contrast", comment: "Contrast label")

    // MARK: - Night Shift

    static let nightShift = NSLocalizedString("nightshift.title", value: "Night Shift", comment: "Night Shift title")
    static let colorTemperature = NSLocalizedString("nightshift.temperature", value: "Color Temperature", comment: "Color temperature label")
    static let schedule = NSLocalizedString("nightshift.schedule", value: "Schedule", comment: "Schedule label")
    static let manual = NSLocalizedString("nightshift.manual", value: "Manual", comment: "Manual mode")
    static let sunsetToSunrise = NSLocalizedString("nightshift.sunset_sunrise", value: "Sunset to Sunrise", comment: "Sunset to sunrise mode")
    static let customSchedule = NSLocalizedString("nightshift.custom", value: "Custom Schedule", comment: "Custom schedule mode")

    // MARK: - Profiles

    static let profiles = NSLocalizedString("profiles.title", value: "Profiles", comment: "Profiles section title")
    static let newProfile = NSLocalizedString("profiles.new", value: "New Profile", comment: "New profile")
    static let profileName = NSLocalizedString("profiles.name", value: "Profile Name", comment: "Profile name label")
    static let applyProfile = NSLocalizedString("profiles.apply", value: "Apply Profile", comment: "Apply profile button")
    static let updateProfile = NSLocalizedString("profiles.update", value: "Update with Current Settings", comment: "Update profile button")

    // MARK: - Quick Dim

    static let quickDim = NSLocalizedString("quickdim.title", value: "Quick Dim", comment: "Quick dim title")
    static let quickDimLevel = NSLocalizedString("quickdim.level", value: "Quick dim level", comment: "Quick dim level label")

    // MARK: - Settings Tabs

    static let general = NSLocalizedString("settings.general", value: "General", comment: "General settings tab")
    static let shortcuts = NSLocalizedString("settings.shortcuts", value: "Shortcuts", comment: "Shortcuts settings tab")
    static let advanced = NSLocalizedString("settings.advanced", value: "Advanced", comment: "Advanced settings tab")

    // MARK: - Permissions

    static let locationPermission = NSLocalizedString("permissions.location", value: "Montr uses your location to calculate sunrise and sunset times for automatic Night Shift scheduling.", comment: "Location permission description")
    static let accessibilityPermission = NSLocalizedString("permissions.accessibility", value: "Montr needs accessibility access to use global keyboard shortcuts.", comment: "Accessibility permission description")
}

// MARK: - String Extension

extension String {
    /// Returns a localized string using self as the key
    var localized: String {
        NSLocalizedString(self, comment: "")
    }

    /// Returns a localized string with format arguments
    func localized(with arguments: CVarArg...) -> String {
        String(format: self.localized, arguments: arguments)
    }
}
