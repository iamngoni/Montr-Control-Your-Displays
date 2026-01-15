import Foundation

/// Night Shift scheduling configuration
struct NightShiftSchedule: Codable, Equatable {
    /// Schedule mode
    var mode: ScheduleMode

    /// Custom time range (for .custom mode)
    var customTimeRange: TimeRange?

    /// Transition duration in minutes
    var transitionDuration: Int

    /// Whether to apply to all displays or per-display
    var applyToAllDisplays: Bool

    // MARK: - Schedule Mode

    enum ScheduleMode: String, Codable, CaseIterable {
        case manual = "Manual"
        case sunsetToSunrise = "Sunset to Sunrise"
        case custom = "Custom Schedule"

        var displayName: String {
            rawValue
        }

        var icon: String {
            switch self {
            case .manual: return "hand.tap"
            case .sunsetToSunrise: return "sun.horizon"
            case .custom: return "clock"
            }
        }
    }

    // MARK: - Initialization

    init(
        mode: ScheduleMode = .manual,
        customTimeRange: TimeRange? = nil,
        transitionDuration: Int = 30,
        applyToAllDisplays: Bool = true
    ) {
        self.mode = mode
        self.customTimeRange = customTimeRange
        self.transitionDuration = transitionDuration.clamped(to: 1...120)
        self.applyToAllDisplays = applyToAllDisplays
    }

    // MARK: - Computed Properties

    /// Whether Night Shift should be active right now based on schedule
    func shouldBeActive(
        currentTime: Date = Date(),
        sunrise: Date? = nil,
        sunset: Date? = nil
    ) -> Bool {
        switch mode {
        case .manual:
            return false // Manual mode doesn't auto-activate

        case .sunsetToSunrise:
            guard let sunrise = sunrise, let sunset = sunset else {
                return false
            }
            let now = currentTime
            // Active between sunset and sunrise
            if sunset < sunrise {
                // Same day scenario (shouldn't happen normally but handle it)
                return now >= sunset && now < sunrise
            } else {
                // Sunset is "today", sunrise is "tomorrow"
                // Active if after sunset OR before sunrise
                return now >= sunset || now < sunrise
            }

        case .custom:
            guard let range = customTimeRange else {
                return false
            }
            return range.contains(currentTime)
        }
    }

    /// Calculate transition progress (0.0 to 1.0) for gradual transitions
    func transitionProgress(
        currentTime: Date,
        targetActiveState: Bool,
        stateChangedAt: Date
    ) -> Double {
        let elapsed = currentTime.timeIntervalSince(stateChangedAt)
        let duration = Double(transitionDuration * 60) // Convert to seconds

        if duration <= 0 {
            return targetActiveState ? 1.0 : 0.0
        }

        let progress = min(elapsed / duration, 1.0)
        return targetActiveState ? progress : (1.0 - progress)
    }
}

// MARK: - Default Schedule

extension NightShiftSchedule {
    static let `default` = NightShiftSchedule(
        mode: .manual,
        customTimeRange: TimeRange(
            start: TimeOfDay(hour: 22, minute: 0),
            end: TimeOfDay(hour: 7, minute: 0)
        ),
        transitionDuration: 30,
        applyToAllDisplays: true
    )
}
