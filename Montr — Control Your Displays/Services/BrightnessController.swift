import Foundation
import CoreGraphics
import Combine

/// Central controller for managing brightness across all displays
@MainActor
final class BrightnessController: ObservableObject, @unchecked Sendable {
    // MARK: - Published Properties

    @Published private(set) var displayBrightness: [String: Int] = [:]
    @Published private(set) var displayContrast: [String: Int] = [:]
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
            await setBuiltInBrightness(value: clampedValue)
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
    }

    private func setupObservers() {
        // Listen for display changes
        NotificationCenter.default.publisher(for: .displaysDidChange)
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
        }
    }

    private func setBuiltInBrightness(value: Int) async {
        let normalizedValue = Float(value) / 100.0
        _ = ddcService.setBuiltInBrightness(normalizedValue)
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
}
