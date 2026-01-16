import Foundation
import CoreGraphics

/// Represents a physical display connected to the system
struct Display: Identifiable, Codable, Hashable {
    /// Unique identifier for the display (CGDirectDisplayID)
    let id: CGDirectDisplayID

    /// Manufacturer name (e.g., "Dell", "LG", "Apple")
    let vendorName: String

    /// Model name (e.g., "U2722D", "27UK850")
    let modelName: String

    /// Serial number if available
    let serialNumber: String?

    /// Whether this is the built-in display
    let isBuiltIn: Bool

    /// Whether the display supports DDC/CI
    var supportsDDC: Bool

    /// Native resolution
    let nativeResolution: CGSize

    /// Current resolution
    var currentResolution: CGSize

    /// Connection type
    let connectionType: ConnectionType

    /// User-assigned custom name
    var customName: String?

    // MARK: - Computed Properties

    /// Display name to show in UI (custom name or model name)
    var displayName: String {
        customName ?? modelName
    }

    /// Subtitle showing original name when custom name is set
    var subtitle: String? {
        customName != nil ? modelName : nil
    }

    /// Brightness control method badge text
    var controlMethodBadge: String {
        if isBuiltIn {
            return "System"
        }
        return supportsDDC ? "DDC/CI" : "Software"
    }

    /// Short display name for tab bar (truncated if too long)
    var shortDisplayName: String {
        let name = displayName
        if name.count > 18 {
            return String(name.prefix(15)) + "..."
        }
        return name
    }

    // MARK: - Connection Type

    enum ConnectionType: String, Codable {
        case builtIn = "Built-in"
        case hdmi = "HDMI"
        case displayPort = "DisplayPort"
        case usbc = "USB-C"
        case thunderbolt = "Thunderbolt"
        case dvi = "DVI"
        case vga = "VGA"
        case unknown = "Unknown"

        /// Human-readable display name
        var displayName: String {
            switch self {
            case .builtIn: return "Built-in Display"
            case .hdmi: return "HDMI"
            case .displayPort: return "DisplayPort"
            case .usbc: return "USB-C"
            case .thunderbolt: return "Thunderbolt"
            case .dvi: return "DVI"
            case .vga: return "VGA"
            case .unknown: return "External Display"
            }
        }
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, vendorName, modelName, serialNumber, isBuiltIn
        case supportsDDC, nativeResolution, currentResolution
        case connectionType, customName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(CGDirectDisplayID.self, forKey: .id)
        vendorName = try container.decode(String.self, forKey: .vendorName)
        modelName = try container.decode(String.self, forKey: .modelName)
        serialNumber = try container.decodeIfPresent(String.self, forKey: .serialNumber)
        isBuiltIn = try container.decode(Bool.self, forKey: .isBuiltIn)
        supportsDDC = try container.decode(Bool.self, forKey: .supportsDDC)

        let nativeWidth = try container.decode(Double.self, forKey: .nativeResolution)
        let nativeHeight = try container.decode(Double.self, forKey: .nativeResolution)
        nativeResolution = CGSize(width: nativeWidth, height: nativeHeight)

        let currentWidth = try container.decode(Double.self, forKey: .currentResolution)
        let currentHeight = try container.decode(Double.self, forKey: .currentResolution)
        currentResolution = CGSize(width: currentWidth, height: currentHeight)

        connectionType = try container.decode(ConnectionType.self, forKey: .connectionType)
        customName = try container.decodeIfPresent(String.self, forKey: .customName)
    }

    init(
        id: CGDirectDisplayID,
        vendorName: String,
        modelName: String,
        serialNumber: String? = nil,
        isBuiltIn: Bool,
        supportsDDC: Bool,
        nativeResolution: CGSize,
        currentResolution: CGSize,
        connectionType: ConnectionType,
        customName: String? = nil
    ) {
        self.id = id
        self.vendorName = vendorName
        self.modelName = modelName
        self.serialNumber = serialNumber
        self.isBuiltIn = isBuiltIn
        self.supportsDDC = supportsDDC
        self.nativeResolution = nativeResolution
        self.currentResolution = currentResolution
        self.connectionType = connectionType
        self.customName = customName
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Display, rhs: Display) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Display Identifier

extension Display {
    /// Stable identifier for matching displays across reconnections
    var stableIdentifier: String {
        if let serial = serialNumber, !serial.isEmpty {
            return "\(vendorName)-\(modelName)-\(serial)"
        }
        return "\(vendorName)-\(modelName)-\(id)"
    }

    /// Whether this is a Sidecar (iPad) display
    /// Sidecar displays use Apple vendor name but are not built-in
    var isSidecar: Bool {
        vendorName == "Apple" && !isBuiltIn
    }

    /// Whether this display supports gamma/color temperature changes
    /// Sidecar displays don't properly support per-display gamma manipulation
    var supportsGamma: Bool {
        !isSidecar
    }

    /// Whether DDC may be limited due to Mac Mini HDMI port
    /// Note: Mac Mini HDMI ports reportedly don't support DDC on Apple Silicon
    /// See: https://alinpanaitiu.com/blog/journey-to-ddc-on-m1-macs/
    var mayHaveHDMIDDCLimitation: Bool {
        #if arch(arm64)
            // On Apple Silicon Mac Mini, HDMI port doesn't support DDC
            return connectionType == .hdmi && !isBuiltIn && !isSidecar
        #else
            return false
        #endif
    }

    /// Whether DDC is expected to work reliably on this display
    /// Takes into account known hardware limitations
    var ddcExpectedReliable: Bool {
        guard supportsDDC else { return false }
        guard !mayHaveHDMIDDCLimitation else { return false }
        return true
    }
}
