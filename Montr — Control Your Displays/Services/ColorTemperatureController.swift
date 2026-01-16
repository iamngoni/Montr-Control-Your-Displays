import Foundation
import CoreGraphics
import Combine

/// Controller for managing color temperature / Night Shift functionality
@MainActor
final class ColorTemperatureController: ObservableObject, @unchecked Sendable {
    // MARK: - Published Properties

    @Published var isEnabled: Bool = false
    @Published var globalTemperature: Int = 6500
    @Published private(set) var perDisplayTemperature: [String: Int] = [:]
    @Published var schedule: NightShiftSchedule = .default
    @Published private(set) var isInTransition: Bool = false

    // MARK: - Private Properties

    private let gammaService = GammaBrightnessService.shared
    private let sunriseSunsetService = SunriseSunsetService.shared
    private var transitionTimer: Timer?
    private var scheduleTimer: Timer?
    private var transitionStartTime: Date?
    private var transitionTargetState: Bool = false
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Singleton

    @MainActor static let shared = ColorTemperatureController()

    private init() {
        loadSavedSettings()
        setupScheduleTimer()
    }

    // MARK: - Public Methods

    /// Get color temperature for a display
    func getTemperature(for display: Display) -> Int {
        if schedule.applyToAllDisplays {
            return globalTemperature
        }
        return perDisplayTemperature[display.stableIdentifier] ?? globalTemperature
    }

    /// Set color temperature for a display
    func setTemperature(for display: Display, kelvin: Int) async {
        let clampedKelvin = max(2700, min(6500, kelvin))
        let identifier = display.stableIdentifier

        if schedule.applyToAllDisplays {
            globalTemperature = clampedKelvin
            // Apply to all displays
            let displays = DisplayManager.shared.displays
            for d in displays {
                await applyTemperature(to: d, kelvin: clampedKelvin)
            }
        } else {
            perDisplayTemperature[identifier] = clampedKelvin
            await applyTemperature(to: display, kelvin: clampedKelvin)
        }

        saveSettings()
    }

    /// Set global color temperature for all displays
    func setGlobalTemperature(_ kelvin: Int) async {
        let clampedKelvin = max(2700, min(6500, kelvin))
        globalTemperature = clampedKelvin

        let displays = DisplayManager.shared.displays
        for display in displays {
            await applyTemperature(to: display, kelvin: clampedKelvin)
        }

        saveSettings()
    }

    /// Toggle Night Shift on/off
    func toggle() async {
        isEnabled.toggle()

        if isEnabled {
            await applyCurrentTemperature()
        } else {
            await disableNightShift()
        }

        saveSettings()
    }

    /// Enable Night Shift
    func enable() async {
        guard !isEnabled else { return }
        isEnabled = true
        await applyCurrentTemperature()
        saveSettings()
    }

    /// Disable Night Shift
    func disable() async {
        guard isEnabled else { return }
        isEnabled = false
        await disableNightShift()
        saveSettings()
    }

    /// Apply a preset temperature
    func applyPreset(_ preset: TemperaturePreset) async {
        globalTemperature = preset.kelvin
        if !isEnabled {
            isEnabled = true
        }
        await applyCurrentTemperature()
        saveSettings()
    }

    /// Start gradual transition
    func startTransition(to enabled: Bool) {
        guard schedule.transitionDuration > 0 else {
            Task {
                if enabled {
                    await enable()
                } else {
                    await disable()
                }
            }
            return
        }

        isInTransition = true
        transitionStartTime = Date()
        transitionTargetState = enabled

        // Start transition timer
        transitionTimer?.invalidate()
        transitionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.updateTransition()
            }
        }
    }

    // MARK: - Private Methods

    private func loadSavedSettings() {
        isEnabled = SettingsManager.shared.nightShiftEnabled
        globalTemperature = SettingsManager.shared.nightShiftTemperature
        perDisplayTemperature = SettingsManager.shared.perDisplayTemperature
        schedule = SettingsManager.shared.nightShiftSchedule
    }

    private func saveSettings() {
        SettingsManager.shared.nightShiftEnabled = isEnabled
        SettingsManager.shared.nightShiftTemperature = globalTemperature
        SettingsManager.shared.perDisplayTemperature = perDisplayTemperature
        SettingsManager.shared.nightShiftSchedule = schedule
    }

    private func setupScheduleTimer() {
        // Check schedule every minute
        scheduleTimer?.invalidate()
        scheduleTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkSchedule()
            }
        }

        // Initial check
        Task {
            await checkSchedule()
        }
    }

    private func checkSchedule() async {
        guard schedule.mode != .manual else { return }

        let sunrise = sunriseSunsetService.sunrise
        let sunset = sunriseSunsetService.sunset

        let shouldBeActive = schedule.shouldBeActive(
            currentTime: Date(),
            sunrise: sunrise,
            sunset: sunset
        )

        if shouldBeActive != isEnabled {
            if schedule.transitionDuration > 0 {
                startTransition(to: shouldBeActive)
            } else {
                if shouldBeActive {
                    await enable()
                } else {
                    await disable()
                }
            }
        }
    }

    private func updateTransition() async {
        guard let startTime = transitionStartTime else {
            stopTransition()
            return
        }

        let progress = schedule.transitionProgress(
            currentTime: Date(),
            targetActiveState: transitionTargetState,
            stateChangedAt: startTime
        )

        if progress >= 1.0 || progress <= 0.0 {
            // Transition complete
            isEnabled = transitionTargetState
            if isEnabled {
                await applyCurrentTemperature()
            } else {
                await disableNightShift()
            }
            stopTransition()
        } else {
            // Interpolate temperature
            let targetTemp = transitionTargetState ? globalTemperature : 6500
            let startTemp = transitionTargetState ? 6500 : globalTemperature
            let currentTemp = Int(Double(startTemp) + (Double(targetTemp - startTemp) * progress))

            let displays = DisplayManager.shared.displays
            for display in displays where display.supportsGamma {
                await applyTemperature(to: display, kelvin: currentTemp)
            }
        }
    }

    private func stopTransition() {
        transitionTimer?.invalidate()
        transitionTimer = nil
        transitionStartTime = nil
        isInTransition = false
    }

    private func applyCurrentTemperature() async {
        let displays = DisplayManager.shared.displays

        for display in displays {
            let temp = getTemperature(for: display)
            await applyTemperature(to: display, kelvin: temp)
        }
    }

    private func applyTemperature(to display: Display, kelvin: Int) async {
        guard isEnabled else { return }

        // Skip Sidecar (iPad) displays - they don't support per-display gamma manipulation
        // Gamma changes to Sidecar displays may incorrectly affect other displays
        guard display.supportsGamma else {
            print("Skipping gamma for Sidecar display: \(display.displayName)")
            return
        }

        let brightness = await BrightnessController.shared.getBrightness(for: display)
        gammaService.applyColorTemperature(
            displayId: display.id,
            kelvin: kelvin,
            brightness: brightness
        )
    }

    private func disableNightShift() async {
        let displays = DisplayManager.shared.displays

        for display in displays {
            // Skip Sidecar displays
            guard display.supportsGamma else { continue }

            // Reset to neutral temperature (6500K) while maintaining brightness
            let brightness = await BrightnessController.shared.getBrightness(for: display)
            gammaService.applyColorTemperature(
                displayId: display.id,
                kelvin: 6500,
                brightness: brightness
            )
        }
    }
}

// MARK: - Temperature Presets

enum TemperaturePreset: CaseIterable {
    case off
    case warm
    case warmer
    case candlelight

    var name: String {
        switch self {
        case .off: return "Off"
        case .warm: return "Warm"
        case .warmer: return "Warmer"
        case .candlelight: return "Candlelight"
        }
    }

    var kelvin: Int {
        switch self {
        case .off: return 6500
        case .warm: return 4000
        case .warmer: return 3400
        case .candlelight: return 2700
        }
    }

    var description: String {
        switch self {
        case .off: return "Native (6500K)"
        case .warm: return "4000K"
        case .warmer: return "3400K"
        case .candlelight: return "2700K"
        }
    }
}
