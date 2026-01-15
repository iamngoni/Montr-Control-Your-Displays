import Foundation
import CoreGraphics

/// Converts color temperature in Kelvin to RGB values
struct KelvinToRGB {
    /// Convert Kelvin temperature to RGB values (0.0 - 1.0)
    static func convert(kelvin: Int) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
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

        return (
            red: CGFloat(red / 255.0),
            green: CGFloat(green / 255.0),
            blue: CGFloat(blue / 255.0)
        )
    }

    /// Convert Kelvin temperature to a gamma table multiplier
    static func toGammaMultipliers(kelvin: Int) -> (red: Float, green: Float, blue: Float) {
        let rgb = convert(kelvin: kelvin)
        return (
            red: Float(rgb.red),
            green: Float(rgb.green),
            blue: Float(rgb.blue)
        )
    }
}

// MARK: - Common Color Temperatures

extension KelvinToRGB {
    /// Standard daylight (6500K)
    static let daylight = 6500

    /// Warm white (4000K)
    static let warmWhite = 4000

    /// Soft white (3400K)
    static let softWhite = 3400

    /// Candlelight (2700K)
    static let candlelight = 2700

    /// Incandescent (2400K)
    static let incandescent = 2400
}
