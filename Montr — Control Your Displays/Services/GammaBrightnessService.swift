import Foundation
import CoreGraphics

/// Service for software-based brightness control using gamma tables
final class GammaBrightnessService {
    // MARK: - Singleton

    static let shared = GammaBrightnessService()
    private init() {}

    // MARK: - Storage

    private var originalGammaTables: [CGDirectDisplayID: GammaTable] = [:]
    private var currentBrightness: [CGDirectDisplayID: Int] = [:]

    // MARK: - Gamma Table

    struct GammaTable {
        var red: [CGGammaValue]
        var green: [CGGammaValue]
        var blue: [CGGammaValue]

        static let tableSize = 256

        init() {
            red = [CGGammaValue](repeating: 0, count: GammaTable.tableSize)
            green = [CGGammaValue](repeating: 0, count: GammaTable.tableSize)
            blue = [CGGammaValue](repeating: 0, count: GammaTable.tableSize)
        }

        init(red: [CGGammaValue], green: [CGGammaValue], blue: [CGGammaValue]) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        /// Create a linear gamma table (no modification)
        static var linear: GammaTable {
            var table = GammaTable()
            for i in 0..<tableSize {
                let value = CGGammaValue(i) / CGGammaValue(tableSize - 1)
                table.red[i] = value
                table.green[i] = value
                table.blue[i] = value
            }
            return table
        }
    }

    // MARK: - Public Methods

    /// Capture and store the original gamma table for a display
    func captureOriginalGamma(for displayId: CGDirectDisplayID) {
        guard originalGammaTables[displayId] == nil else { return }

        var table = GammaTable()
        var sampleCount: UInt32 = 0

        let result = CGGetDisplayTransferByTable(
            displayId,
            UInt32(GammaTable.tableSize),
            &table.red,
            &table.green,
            &table.blue,
            &sampleCount
        )

        if result == .success {
            originalGammaTables[displayId] = table
        }
    }

    /// Restore the original gamma table for a display
    func restoreOriginalGamma(for displayId: CGDirectDisplayID) {
        guard let original = originalGammaTables[displayId] else { return }

        CGSetDisplayTransferByTable(
            displayId,
            UInt32(GammaTable.tableSize),
            original.red,
            original.green,
            original.blue
        )

        currentBrightness.removeValue(forKey: displayId)
    }

    /// Restore original gamma for all displays
    func restoreAllOriginalGamma() {
        for displayId in originalGammaTables.keys {
            restoreOriginalGamma(for: displayId)
        }
    }

    /// Set software brightness for a display (0-100)
    func setBrightness(displayId: CGDirectDisplayID, brightness: Int) {
        // Ensure we have the original gamma captured
        captureOriginalGamma(for: displayId)

        let normalizedBrightness = CGGammaValue(max(0, min(100, brightness))) / 100.0

        // Get original or linear gamma
        let baseTable = originalGammaTables[displayId] ?? GammaTable.linear

        // Apply brightness reduction
        var newTable = GammaTable()
        for i in 0..<GammaTable.tableSize {
            newTable.red[i] = baseTable.red[i] * normalizedBrightness
            newTable.green[i] = baseTable.green[i] * normalizedBrightness
            newTable.blue[i] = baseTable.blue[i] * normalizedBrightness
        }

        CGSetDisplayTransferByTable(
            displayId,
            UInt32(GammaTable.tableSize),
            newTable.red,
            newTable.green,
            newTable.blue
        )

        currentBrightness[displayId] = brightness
    }

    /// Get current software brightness for a display
    func getBrightness(for displayId: CGDirectDisplayID) -> Int {
        return currentBrightness[displayId] ?? 100
    }

    /// Apply color temperature adjustment (in Kelvin)
    func applyColorTemperature(displayId: CGDirectDisplayID, kelvin: Int, brightness: Int = 100) {
        captureOriginalGamma(for: displayId)

        let rgb = kelvinToRGB(kelvin: kelvin)
        let normalizedBrightness = CGGammaValue(max(0, min(100, brightness))) / 100.0

        let baseTable = originalGammaTables[displayId] ?? GammaTable.linear

        var newTable = GammaTable()
        for i in 0..<GammaTable.tableSize {
            newTable.red[i] = baseTable.red[i] * rgb.red * normalizedBrightness
            newTable.green[i] = baseTable.green[i] * rgb.green * normalizedBrightness
            newTable.blue[i] = baseTable.blue[i] * rgb.blue * normalizedBrightness
        }

        CGSetDisplayTransferByTable(
            displayId,
            UInt32(GammaTable.tableSize),
            newTable.red,
            newTable.green,
            newTable.blue
        )

        currentBrightness[displayId] = brightness
    }

    // MARK: - Color Temperature Conversion

    private func kelvinToRGB(kelvin: Int) -> (red: CGGammaValue, green: CGGammaValue, blue: CGGammaValue) {
        // Clamp temperature to valid range
        let temp = Double(max(1000, min(40000, kelvin))) / 100.0

        var red: Double
        var green: Double
        var blue: Double

        // Calculate red
        if temp <= 66 {
            red = 255
        } else {
            red = temp - 60
            red = 329.698727446 * pow(red, -0.1332047592)
            red = max(0, min(255, red))
        }

        // Calculate green
        if temp <= 66 {
            green = temp
            green = 99.4708025861 * log(green) - 161.1195681661
            green = max(0, min(255, green))
        } else {
            green = temp - 60
            green = 288.1221695283 * pow(green, -0.0755148492)
            green = max(0, min(255, green))
        }

        // Calculate blue
        if temp >= 66 {
            blue = 255
        } else if temp <= 19 {
            blue = 0
        } else {
            blue = temp - 10
            blue = 138.5177312231 * log(blue) - 305.0447927307
            blue = max(0, min(255, blue))
        }

        // Normalize to 0-1
        return (
            red: CGGammaValue(red / 255.0),
            green: CGGammaValue(green / 255.0),
            blue: CGGammaValue(blue / 255.0)
        )
    }
}

// MARK: - Original Settings Storage

extension GammaBrightnessService {
    /// Get original gamma table for persistence
    func getOriginalGammaData(for displayId: CGDirectDisplayID) -> OriginalDisplaySettings? {
        guard let table = originalGammaTables[displayId] else { return nil }

        return OriginalDisplaySettings(
            displayId: String(displayId),
            brightness: 100, // Original brightness assumed to be 100%
            gammaRed: table.red.map { Float($0) },
            gammaGreen: table.green.map { Float($0) },
            gammaBlue: table.blue.map { Float($0) }
        )
    }

    /// Restore from persisted original settings
    func restoreFromPersistedSettings(_ settings: OriginalDisplaySettings) {
        guard let displayId = CGDirectDisplayID(settings.displayId) else { return }

        let table = GammaTable(
            red: settings.gammaRed.map { CGGammaValue($0) },
            green: settings.gammaGreen.map { CGGammaValue($0) },
            blue: settings.gammaBlue.map { CGGammaValue($0) }
        )

        originalGammaTables[displayId] = table
    }
}
