import Foundation

/// Trigger conditions for automatic profile activation
struct AutoActivationTrigger: Codable, Equatable, Identifiable {
    let id: UUID

    /// Type of trigger
    let type: TriggerType

    /// Display identifiers that must be connected (for .connectedDisplays type)
    var requiredDisplayIds: Set<String>?

    /// Time range for activation (for .timeOfDay type)
    var timeRange: TimeRange?

    /// Power source requirement (for .powerSource type)
    var requiresBattery: Bool?

    // MARK: - Trigger Type

    enum TriggerType: String, Codable, CaseIterable {
        case connectedDisplays = "Connected Displays"
        case timeOfDay = "Time of Day"
        case powerSource = "Power Source"
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        type: TriggerType,
        requiredDisplayIds: Set<String>? = nil,
        timeRange: TimeRange? = nil,
        requiresBattery: Bool? = nil
    ) {
        self.id = id
        self.type = type
        self.requiredDisplayIds = requiredDisplayIds
        self.timeRange = timeRange
        self.requiresBattery = requiresBattery
    }

    // MARK: - Evaluation

    func isSatisfied(
        connectedDisplayIds: Set<String>,
        currentTime: Date,
        isOnBattery: Bool
    ) -> Bool {
        switch type {
        case .connectedDisplays:
            guard let required = requiredDisplayIds else { return true }
            return required.isSubset(of: connectedDisplayIds)

        case .timeOfDay:
            guard let range = timeRange else { return true }
            return range.contains(currentTime)

        case .powerSource:
            guard let requiresBattery = requiresBattery else { return true }
            return requiresBattery == isOnBattery
        }
    }
}

// MARK: - Time of Day

struct TimeOfDay: Codable, Equatable, Comparable {
    var hour: Int
    var minute: Int

    var totalMinutes: Int {
        hour * 60 + minute
    }

    static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.totalMinutes < rhs.totalMinutes
    }

    static func from(_ date: Date) -> TimeOfDay {
        let calendar = Calendar.current
        return TimeOfDay(
            hour: calendar.component(.hour, from: date),
            minute: calendar.component(.minute, from: date)
        )
    }
}

// MARK: - Time Range

struct TimeRange: Codable, Equatable {
    var start: TimeOfDay
    var end: TimeOfDay

    /// Whether the range spans midnight
    var spansMidnight: Bool {
        start > end
    }

    /// Check if a given time is within this range
    func contains(_ date: Date) -> Bool {
        let time = TimeOfDay.from(date)

        if spansMidnight {
            // Range like 22:00 - 07:00
            return time >= start || time < end
        } else {
            // Range like 09:00 - 17:00
            return time >= start && time < end
        }
    }
}
