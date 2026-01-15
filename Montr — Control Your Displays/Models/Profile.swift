import Foundation

/// A saved display configuration profile
struct Profile: Identifiable, Codable, Equatable, Hashable {
    /// Unique identifier
    let id: UUID

    /// Profile name
    var name: String

    /// Settings for each display in this profile
    var displaySettings: [DisplaySettings]

    /// Whether quick dim is enabled in this profile
    var quickDimEnabled: Bool

    /// Auto-activation triggers
    var triggers: [AutoActivationTrigger]

    /// Creation date
    let createdAt: Date

    /// Last modified date
    var modifiedAt: Date

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        name: String,
        displaySettings: [DisplaySettings] = [],
        quickDimEnabled: Bool = false,
        triggers: [AutoActivationTrigger] = [],
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.displaySettings = displaySettings
        self.quickDimEnabled = quickDimEnabled
        self.triggers = triggers
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    // MARK: - Methods

    /// Get settings for a specific display
    func settings(for displayId: String) -> DisplaySettings? {
        displaySettings.first { $0.displayId == displayId }
    }

    /// Update settings for a specific display
    mutating func updateSettings(_ settings: DisplaySettings) {
        if let index = displaySettings.firstIndex(where: { $0.displayId == settings.displayId }) {
            displaySettings[index] = settings
        } else {
            displaySettings.append(settings)
        }
        modifiedAt = Date()
    }

    /// Check if this profile should auto-activate given current conditions
    func shouldActivate(
        connectedDisplayIds: Set<String>,
        currentTime: Date,
        isOnBattery: Bool
    ) -> Bool {
        guard !triggers.isEmpty else { return false }

        return triggers.allSatisfy { trigger in
            trigger.isSatisfied(
                connectedDisplayIds: connectedDisplayIds,
                currentTime: currentTime,
                isOnBattery: isOnBattery
            )
        }
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Default Profiles

extension Profile {
    static let defaultProfiles: [Profile] = [
        Profile(
            name: "Work",
            displaySettings: [],
            triggers: []
        ),
        Profile(
            name: "Movie",
            displaySettings: [],
            triggers: []
        ),
        Profile(
            name: "Night",
            displaySettings: [],
            triggers: [
                AutoActivationTrigger(
                    type: .timeOfDay,
                    timeRange: TimeRange(start: TimeOfDay(hour: 22, minute: 0), end: TimeOfDay(hour: 7, minute: 0))
                )
            ]
        )
    ]
}
