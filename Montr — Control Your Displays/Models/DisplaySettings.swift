import Foundation

/// Settings for a single display
struct DisplaySettings: Codable, Equatable {
    /// Display identifier (stableIdentifier from Display)
    let displayId: String

    /// Brightness level (0-100)
    var brightness: Int

    /// Contrast level (0-100), only applicable for DDC displays
    var contrast: Int?

    /// Color temperature in Kelvin (2700-6500)
    var colorTemperature: Int

    /// Whether Night Shift is enabled for this display
    var nightShiftEnabled: Bool

    // MARK: - Initialization

    init(
        displayId: String,
        brightness: Int = 75,
        contrast: Int? = nil,
        colorTemperature: Int = 6500,
        nightShiftEnabled: Bool = false
    ) {
        self.displayId = displayId
        self.brightness = brightness.clamped(to: 0...100)
        self.contrast = contrast?.clamped(to: 0...100)
        self.colorTemperature = colorTemperature.clamped(to: 2700...6500)
        self.nightShiftEnabled = nightShiftEnabled
    }

    // MARK: - Validation

    mutating func clampValues() {
        brightness = brightness.clamped(to: 0...100)
        contrast = contrast?.clamped(to: 0...100)
        colorTemperature = colorTemperature.clamped(to: 2700...6500)
    }
}

// MARK: - Int Clamping Extension

extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Original Display Settings

/// Stores original display settings for restoration on quit
struct OriginalDisplaySettings: Codable {
    let displayId: String
    let brightness: Int
    let gammaRed: [Float]
    let gammaGreen: [Float]
    let gammaBlue: [Float]
    let capturedAt: Date

    init(displayId: String, brightness: Int, gammaRed: [Float], gammaGreen: [Float], gammaBlue: [Float]) {
        self.displayId = displayId
        self.brightness = brightness
        self.gammaRed = gammaRed
        self.gammaGreen = gammaGreen
        self.gammaBlue = gammaBlue
        self.capturedAt = Date()
    }
}
