import Foundation
import CoreGraphics
import Combine

/// Central controller for managing brightness across all displays
@MainActor
final class BrightnessController: ObservableObject, @unchecked Sendable {
    // MARK: - Published Properties

    @Published private(set) var displayBrightness: [String: Int] = [:]
    @Published private(set) var displayContrast: [String: Int] = [:]
    @Published private(set) var displayVolume: [String: Int] = [:]
    @Published private(set) var displayMuted: [String: Bool] = [:]
    @Published private(set) var volumeSupportedDisplays: Set<String> = []
    @Published var quickDimEnabled: Bool = false
    @Published var syncAllDisplays: Bool = false

    // MARK: - Private Properties

    private let ddcService = DDCService.shared
    private let gammaService = GammaBrightnessService.shared
    private var brightnessBeforeQuickDim: [String: Int] = [:]
    private var cancellables = Set<AnyCancellable>()
    private let ddcQueue = DispatchQueue(label: "com.montr.ddc", qos: .userInitiated)

    // MARK: - Singleton

    @MainActor static let shared = BrightnessController()

    private init() {
        loadSavedBrightness()
        setupObservers()
    }

    // MARK: - Public Methods

    /// Get brightness for a display
    func getBrightness(for display: Display) -> Int {
        displayBrightness[display.stableIdentifier] ?? 75
    }

    /// Set brightness for a display
    func setBrightness(for display: Display, value: Int) async {
        let clampedValue = max(0, min(100, value))
        let identifier = display.stableIdentifier

        // Update published state
        displayBrightness[identifier] = clampedValue

        // Apply to hardware/software
        if display.isBuiltIn {
            await setBuiltInBrightness(value: clampedValue, displayId: display.id)
        } else if display.supportsDDC {
            await setDDCBrightness(displayId: display.id, value: clampedValue)
        } else {
            await setGammaBrightness(displayId: display.id, value: clampedValue)
        }

        // Save to settings
        SettingsManager.shared.saveBrightness(clampedValue, for: identifier)

        // Post notification for HUD
        NotificationCenter.default.post(
            name: .brightnessDidChange,
            object: nil,
            userInfo: ["displayId": identifier, "brightness": clampedValue]
        )
    }

    /// Get contrast for a display
    func getContrast(for display: Display) -> Int {
        displayContrast[display.stableIdentifier] ?? 75
    }

    /// Set contrast for a display (DDC only)
    func setContrast(for display: Display, value: Int) async {
        guard display.supportsDDC && !display.isBuiltIn else { return }

        let clampedValue = max(0, min(100, value))
        let identifier = display.stableIdentifier

        displayContrast[identifier] = clampedValue

        // Run DDC command on background queue to prevent UI freezing
        let ddcService = self.ddcService
        let displayId = display.id
        await withCheckedContinuation { continuation in
            ddcQueue.async {
                do {
                    try ddcService.setContrast(displayId: displayId, value: clampedValue)
                } catch {
                    print("Failed to set contrast via DDC: \(error)")
                }
                continuation.resume()
            }
        }

        SettingsManager.shared.saveContrast(clampedValue, for: identifier)
    }

    // MARK: - Volume Control

    /// Check if a display supports volume control
    func supportsVolume(for display: Display) -> Bool {
        volumeSupportedDisplays.contains(display.stableIdentifier)
    }

    /// Get volume for a display
    func getVolume(for display: Display) -> Int {
        displayVolume[display.stableIdentifier] ?? 50
    }

    /// Set volume for a display (DDC only)
    func setVolume(for display: Display, value: Int) async {
        guard display.supportsDDC && !display.isBuiltIn else { return }
        guard supportsVolume(for: display) else { return }

        let clampedValue = max(0, min(100, value))
        let identifier = display.stableIdentifier

        displayVolume[identifier] = clampedValue

        // Run DDC command on background queue to prevent UI freezing
        let ddcService = self.ddcService
        let displayId = display.id
        await withCheckedContinuation { continuation in
            ddcQueue.async {
                do {
                    try ddcService.setVolume(displayId: displayId, value: clampedValue)
                } catch {
                    print("Failed to set volume via DDC: \(error)")
                }
                continuation.resume()
            }
        }

        SettingsManager.shared.saveVolume(clampedValue, for: identifier)

        // Post notification for potential HUD
        NotificationCenter.default.post(
            name: .volumeDidChange,
            object: nil,
            userInfo: ["displayId": identifier, "volume": clampedValue]
        )
    }

    /// Get mute state for a display
    func isMuted(for display: Display) -> Bool {
        displayMuted[display.stableIdentifier] ?? false
    }

    /// Toggle mute for a display
    func toggleMute(for display: Display) async {
        guard display.supportsDDC && !display.isBuiltIn else { return }
        guard supportsVolume(for: display) else { return }

        let identifier = display.stableIdentifier
        let currentMuted = displayMuted[identifier] ?? false
        let newMuted = !currentMuted

        displayMuted[identifier] = newMuted

        // Run DDC command on background queue
        let ddcService = self.ddcService
        let displayId = display.id
        await withCheckedContinuation { continuation in
            ddcQueue.async {
                do {
                    try ddcService.setMute(displayId: displayId, muted: newMuted)
                } catch {
                    print("Failed to set mute via DDC: \(error)")
                }
                continuation.resume()
            }
        }

        SettingsManager.shared.saveMuted(newMuted, for: identifier)
    }

    /// Set mute state for a display
    func setMuted(for display: Display, muted: Bool) async {
        guard display.supportsDDC && !display.isBuiltIn else { return }
        guard supportsVolume(for: display) else { return }

        let identifier = display.stableIdentifier
        displayMuted[identifier] = muted

        let ddcService = self.ddcService
        let displayId = display.id
        await withCheckedContinuation { continuation in
            ddcQueue.async {
                do {
                    try ddcService.setMute(displayId: displayId, muted: muted)
                } catch {
                    print("Failed to set mute via DDC: \(error)")
                }
                continuation.resume()
            }
        }

        SettingsManager.shared.saveMuted(muted, for: identifier)
    }

    /// Adjust volume by delta for all displays that support it
    func adjustVolumeForAll(by delta: Int) async {
        let displays = await DisplayManager.shared.displays

        for display in displays where supportsVolume(for: display) {
            let current = getVolume(for: display)
            let newValue = current + delta
            await setVolume(for: display, value: newValue)
        }
    }

    /// Adjust brightness by delta for all displays
    func adjustBrightnessForAll(by delta: Int) async {
        let displays = await DisplayManager.shared.displays

        for display in displays {
            let current = getBrightness(for: display)
            let newValue = current + delta
            await setBrightness(for: display, value: newValue)
        }
    }

    /// Toggle quick dim
    func toggleQuickDim() async {
        let displays = await DisplayManager.shared.displays

        if quickDimEnabled {
            // Restore previous brightness
            for display in displays {
                if let previous = brightnessBeforeQuickDim[display.stableIdentifier] {
                    await setBrightness(for: display, value: previous)
                }
            }
            brightnessBeforeQuickDim.removeAll()
            quickDimEnabled = false
        } else {
            // Save current brightness and dim
            let quickDimLevel = SettingsManager.shared.quickDimPercentage

            for display in displays {
                let current = getBrightness(for: display)
                brightnessBeforeQuickDim[display.stableIdentifier] = current
                await setBrightness(for: display, value: quickDimLevel)
            }
            quickDimEnabled = true
        }
    }

    /// Sync brightness across all displays to a single value
    func syncAllDisplays(to value: Int) async {
        let displays = await DisplayManager.shared.displays

        for display in displays {
            await setBrightness(for: display, value: value)
        }
    }

    /// Capture original settings for restoration on quit
    func captureOriginalSettings() {
        let displays = DisplayManager.shared.displays

        for display in displays {
            gammaService.captureOriginalGamma(for: display.id)
        }
    }

    /// Restore original settings (called on quit)
    func restoreOriginalSettings() {
        gammaService.restoreAllOriginalGamma()
    }

    // MARK: - Private Methods

    private func loadSavedBrightness() {
        displayBrightness = SettingsManager.shared.savedBrightness
        displayContrast = SettingsManager.shared.savedContrast
        displayVolume = SettingsManager.shared.savedVolume
        displayMuted = SettingsManager.shared.savedMuted
    }

    private func setupObservers() {
        // Listen for display refresh completion (not the raw display change trigger)
        NotificationCenter.default.publisher(for: .displaysRefreshed)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.onDisplaysChanged()
                }
            }
            .store(in: &cancellables)
    }

    private func onDisplaysChanged() async {
        // Apply saved brightness to newly connected displays
        let displays = DisplayManager.shared.displays

        for display in displays {
            let identifier = display.stableIdentifier
            if let savedBrightness = displayBrightness[identifier] {
                await setBrightness(for: display, value: savedBrightness)
            }

            // Check volume support for ALL external displays (not just DDC brightness-supported)
            // Some monitors support volume DDC even if brightness DDC fails
            if !display.isBuiltIn && !display.isSidecar {
                await checkVolumeSupport(for: display)
            }
        }
    }

    private func checkVolumeSupport(for display: Display) async {
        let ddcService = self.ddcService
        let displayId = display.id
        let identifier = display.stableIdentifier

        print("BrightnessController: Checking volume support for \(display.displayName) (DDC: \(display.supportsDDC))")

        let supported = await withCheckedContinuation { continuation in
            ddcQueue.async {
                let result = ddcService.supportsVolume(displayId: displayId)
                continuation.resume(returning: result)
            }
        }

        print("BrightnessController: Volume support for \(display.displayName): \(supported)")

        if supported {
            volumeSupportedDisplays.insert(identifier)

            // Load saved volume if available
            if let savedVolume = displayVolume[identifier] {
                displayVolume[identifier] = savedVolume
            } else {
                // Try to read current volume from display
                let currentVolume = await withCheckedContinuation { continuation in
                    ddcQueue.async {
                        do {
                            let volume = try ddcService.readVolume(displayId: displayId)
                            continuation.resume(returning: volume)
                        } catch {
                            continuation.resume(returning: 50) // Default
                        }
                    }
                }
                displayVolume[identifier] = currentVolume
            }
        } else {
            volumeSupportedDisplays.remove(identifier)
        }
    }

    private func setBuiltInBrightness(value: Int, displayId: CGDirectDisplayID) async {
        let normalizedValue = Float(value) / 100.0
        _ = ddcService.setBuiltInBrightness(normalizedValue)

        // Force a display refresh by touching the gamma table
        // This ensures the brightness change is immediately visible
        // (CoreDisplay API sometimes doesn't trigger an immediate visual update)
        triggerDisplayRefresh(displayId: displayId)
    }

    /// Trigger a display refresh by doing a no-op gamma table write
    private func triggerDisplayRefresh(displayId: CGDirectDisplayID) {
        // Read current gamma and immediately re-apply it
        // This forces the display to refresh without changing anything
        var redTable = [CGGammaValue](repeating: 0, count: 256)
        var greenTable = [CGGammaValue](repeating: 0, count: 256)
        var blueTable = [CGGammaValue](repeating: 0, count: 256)
        var sampleCount: UInt32 = 0

        let readResult = CGGetDisplayTransferByTable(
            displayId,
            256,
            &redTable,
            &greenTable,
            &blueTable,
            &sampleCount
        )

        guard readResult == .success, sampleCount > 0 else { return }

        // Re-apply the same gamma table to force a refresh
        CGSetDisplayTransferByTable(
            displayId,
            sampleCount,
            redTable,
            greenTable,
            blueTable
        )
    }

    private func setDDCBrightness(displayId: CGDirectDisplayID, value: Int) async {
        // Run DDC command on background queue to prevent UI freezing
        let ddcService = self.ddcService
        let success = await withCheckedContinuation { continuation in
            ddcQueue.async {
                do {
                    try ddcService.setBrightness(displayId: displayId, value: value)
                    continuation.resume(returning: true)
                } catch {
                    print("DDC brightness failed: \(error)")
                    continuation.resume(returning: false)
                }
            }
        }

        // Fall back to gamma brightness if DDC failed
        if !success {
            await setGammaBrightness(displayId: displayId, value: value)
        }
    }

    private func setGammaBrightness(displayId: CGDirectDisplayID, value: Int) async {
        gammaService.setBrightness(displayId: displayId, brightness: value)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let brightnessDidChange = Notification.Name("brightnessDidChange")
    static let volumeDidChange = Notification.Name("volumeDidChange")
}
