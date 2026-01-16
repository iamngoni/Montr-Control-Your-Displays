import Foundation
import CoreGraphics
import Combine
import IOKit

// Private API declaration for getting IOKit service port for a display
@_silgen_name("CGDisplayIOServicePort")
private func CGDisplayIOServicePort(_ display: CGDirectDisplayID) -> io_service_t

/// Manages display detection and enumeration
@MainActor
final class DisplayManager: ObservableObject, @unchecked Sendable {
    // MARK: - Published Properties

    @Published private(set) var displays: [Display] = []
    @Published private(set) var isLoading = false

    // MARK: - Private Properties

    private var displayReconfigurationCallback: CGDisplayReconfigurationCallBack?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Singleton

    @MainActor static let shared = DisplayManager()

    private init() {
        setupDisplayReconfigurationCallback()
        Task {
            await refreshDisplays()
        }
    }

    deinit {
        // Note: CGDisplayRemoveReconfigurationCallback would be called here
        // but we're using a singleton pattern so this won't be called
    }

    // MARK: - Public Methods

    /// Refresh the list of connected displays
    func refreshDisplays() async {
        isLoading = true
        defer { isLoading = false }

        var displayIds = [CGDirectDisplayID](repeating: 0, count: 16)
        var displayCount: UInt32 = 0

        let result = CGGetActiveDisplayList(16, &displayIds, &displayCount)
        guard result == .success else {
            print("Failed to get display list: \(result)")
            return
        }

        var newDisplays: [Display] = []

        for i in 0..<Int(displayCount) {
            let displayId = displayIds[i]
            if let display = createDisplay(from: displayId) {
                newDisplays.append(display)
            }
        }

        // Sort: built-in first, then by name
        newDisplays.sort { lhs, rhs in
            if lhs.isBuiltIn != rhs.isBuiltIn {
                return lhs.isBuiltIn
            }
            return lhs.displayName < rhs.displayName
        }

        displays = newDisplays
    }

    /// Get a display by ID
    func display(for id: CGDirectDisplayID) -> Display? {
        displays.first { $0.id == id }
    }

    /// Get a display by stable identifier
    func display(forStableId stableId: String) -> Display? {
        displays.first { $0.stableIdentifier == stableId }
    }

    /// Get all connected display stable identifiers
    var connectedDisplayIds: Set<String> {
        Set(displays.map { $0.stableIdentifier })
    }

    // MARK: - Private Methods

    private func setupDisplayReconfigurationCallback() {
        // Create a callback that posts a notification when displays change
        let callback: CGDisplayReconfigurationCallBack = { displayId, flags, userInfo in
            // Post notification to refresh displays
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .displaysDidChange,
                    object: nil,
                    userInfo: ["displayId": displayId, "flags": flags.rawValue]
                )
            }
        }

        CGDisplayRegisterReconfigurationCallback(callback, nil)

        // Listen for the notification
        NotificationCenter.default.publisher(for: .displaysDidChange)
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.refreshDisplays()
                }
            }
            .store(in: &cancellables)
    }

    private func createDisplay(from displayId: CGDirectDisplayID) -> Display? {
        let isBuiltIn = CGDisplayIsBuiltin(displayId) != 0

        // Get display info
        let vendorNumber = CGDisplayVendorNumber(displayId)
        let modelNumber = CGDisplayModelNumber(displayId)
        let serialNumber = CGDisplaySerialNumber(displayId)

        // Get vendor name
        let vendorName = vendorName(for: vendorNumber)
        let modelName = modelName(for: displayId, vendorNumber: vendorNumber, modelNumber: modelNumber, isBuiltIn: isBuiltIn)

        // Get resolution
        let bounds = CGDisplayBounds(displayId)
        let currentResolution = CGSize(width: bounds.width, height: bounds.height)

        // Get native resolution from display mode
        var nativeResolution = currentResolution
        if let mode = CGDisplayCopyDisplayMode(displayId) {
            nativeResolution = CGSize(
                width: CGFloat(mode.pixelWidth),
                height: CGFloat(mode.pixelHeight)
            )
        }

        // Determine connection type
        let connectionType = determineConnectionType(for: displayId, isBuiltIn: isBuiltIn)

        // Check DDC support by actually testing it
        var supportsDDC = false
        if !isBuiltIn {
            // Sidecar displays (iPads) use Apple vendor ID but don't support DDC
            // Also check for virtual displays which won't support DDC
            let isSidecarOrVirtual = vendorNumber == 0x0610 && !isBuiltIn

            if !isSidecarOrVirtual {
                // Actually test DDC by trying to read brightness
                supportsDDC = DDCService.shared.supportsDDC(displayId: displayId)
            }
        }

        return Display(
            id: displayId,
            vendorName: vendorName,
            modelName: modelName,
            serialNumber: serialNumber > 0 ? String(serialNumber) : nil,
            isBuiltIn: isBuiltIn,
            supportsDDC: supportsDDC,
            nativeResolution: nativeResolution,
            currentResolution: currentResolution,
            connectionType: connectionType,
            customName: SettingsManager.shared.customName(for: "\(displayId)")
        )
    }

    private func vendorName(for vendorNumber: UInt32) -> String {
        // Common vendor IDs
        switch vendorNumber {
        case 0x10AC: return "Dell"
        case 0x1E6D: return "LG"
        case 0x4C2D: return "Samsung"
        case 0x0469: return "ASUS"
        case 0x05E3: return "ViewSonic"
        case 0x0724: return "Acer"
        case 0x170E: return "BenQ"
        case 0x34AC: return "MSI"
        case 0x0610: return "Apple"
        case 0x220E: return "HP"
        case 0x4DD9: return "Lenovo"
        case 0x5262: return "Philips"
        case 0x3284: return "AOC"
        default: return "Display"
        }
    }

    private func modelName(for displayId: CGDirectDisplayID, vendorNumber: UInt32, modelNumber: UInt32, isBuiltIn: Bool) -> String {
        if isBuiltIn {
            return getBuiltInDisplayName()
        }

        // Try to get the display name from IOKit
        if let name = getDisplayNameFromIOKit(displayId: displayId) {
            return name
        }

        // Fallback to vendor + model number
        let vendor = vendorName(for: vendorNumber)
        return "\(vendor) Display \(modelNumber)"
    }

    private func getBuiltInDisplayName() -> String {
        // Get Mac model to determine built-in display name
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let modelString = String(cString: model)

        if modelString.contains("MacBookPro") {
            return "Built-in Retina Display"
        } else if modelString.contains("MacBookAir") {
            return "Built-in Retina Display"
        } else if modelString.contains("iMac") {
            return "Built-in Retina Display"
        } else if modelString.contains("Mac") {
            return "Built-in Display"
        }

        return "Built-in Display"
    }

    private func getDisplayNameFromIOKit(displayId: CGDirectDisplayID) -> String? {
        // Method 1: Try using CGDisplayIOServicePort (deprecated but reliable)
        if let name = getDisplayNameViaServicePort(displayId: displayId) {
            return name
        }

        // Method 2: Fallback to iterating all displays and matching
        return getDisplayNameViaIteration(displayId: displayId)
    }

    private func getDisplayNameViaServicePort(displayId: CGDirectDisplayID) -> String? {
        // Use the deprecated but reliable CGDisplayIOServicePort
        let service = CGDisplayIOServicePort(displayId)
        guard service != 0 else { return nil }

        // Get the display info dictionary
        guard let infoDict = IODisplayCreateInfoDictionary(service, IOOptionBits(kIODisplayOnlyPreferredName))?.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        // Extract the localized product name
        if let names = infoDict[kDisplayProductName] as? [String: String],
           let name = names.values.first, !name.isEmpty {
            return name
        }

        return nil
    }

    private func getDisplayNameViaIteration(displayId: CGDirectDisplayID) -> String? {
        // Get the target display's vendor and product IDs
        let targetVendor = CGDisplayVendorNumber(displayId)
        let targetModel = CGDisplayModelNumber(displayId)
        let targetSerial = CGDisplaySerialNumber(displayId)

        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IODisplayConnect")

        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }

        defer { IOObjectRelease(iterator) }

        var bestMatch: String?
        var exactMatchFound = false

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            // Get display info dictionary which contains vendor/product IDs and name
            guard let infoDict = IODisplayCreateInfoDictionary(service, IOOptionBits(kIODisplayOnlyPreferredName))?.takeRetainedValue() as? [String: Any] else {
                continue
            }

            // Check if this is our target display by matching vendor and product IDs
            guard let vendorId = infoDict[kDisplayVendorID] as? UInt32,
                  let productId = infoDict[kDisplayProductID] as? UInt32 else {
                continue
            }

            // Get serial number if available
            let serialNumber = infoDict[kDisplaySerialNumber] as? UInt32 ?? 0

            // Match by vendor and model
            if vendorId == targetVendor && productId == targetModel {
                // Found matching display - get the localized name from EDID
                if let names = infoDict[kDisplayProductName] as? [String: String],
                   let name = names.values.first, !name.isEmpty {

                    // Prefer exact match including serial
                    if serialNumber == targetSerial || targetSerial == 0 {
                        return name  // Exact match
                    }

                    // Keep as candidate if not exact match
                    if !exactMatchFound {
                        bestMatch = name
                    }
                }
            }
        }

        return bestMatch
    }

    private func determineConnectionType(for displayId: CGDirectDisplayID, isBuiltIn: Bool) -> Display.ConnectionType {
        if isBuiltIn {
            return .builtIn
        }

        // Try to determine from IOKit by examining the display's transport type
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOFramebuffer")

        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return .unknown
        }
        defer { IOObjectRelease(iterator) }

        let targetVendor = CGDisplayVendorNumber(displayId)
        let targetModel = CGDisplayModelNumber(displayId)

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            // Find the display connect child
            var displayIterator: io_iterator_t = 0
            guard IORegistryEntryGetChildIterator(service, kIOServicePlane, &displayIterator) == KERN_SUCCESS else {
                continue
            }
            defer { IOObjectRelease(displayIterator) }

            var displayService = IOIteratorNext(displayIterator)
            while displayService != 0 {
                defer {
                    IOObjectRelease(displayService)
                    displayService = IOIteratorNext(displayIterator)
                }

                // Check if this is our target display
                var vendorId: UInt32 = 0
                var productId: UInt32 = 0

                if let vendorRef = IORegistryEntryCreateCFProperty(displayService, "DisplayVendorID" as CFString, kCFAllocatorDefault, 0) {
                    if let num = vendorRef.takeRetainedValue() as? NSNumber {
                        vendorId = num.uint32Value
                    }
                }

                if let productRef = IORegistryEntryCreateCFProperty(displayService, "DisplayProductID" as CFString, kCFAllocatorDefault, 0) {
                    if let num = productRef.takeRetainedValue() as? NSNumber {
                        productId = num.uint32Value
                    }
                }

                if vendorId != targetVendor || productId != targetModel {
                    continue
                }

                // Found matching display, now check connection type by examining parent framebuffer
                // Look for connection type in the IOFramebuffer properties
                if let connectionTypeRef = IORegistryEntryCreateCFProperty(service, "IODisplayConnectorType" as CFString, kCFAllocatorDefault, 0) {
                    if let connectionType = connectionTypeRef.takeRetainedValue() as? NSNumber {
                        return connectionTypeFromIOKit(connectionType.uint32Value)
                    }
                }

                // Alternative: Check IOFBTransform or IODisplayParameters for connector info
                if let ioClass = IORegistryEntryCreateCFProperty(service, "IOClass" as CFString, kCFAllocatorDefault, 0) {
                    if let className = ioClass.takeRetainedValue() as? String {
                        // Check common framebuffer class names
                        if className.contains("DisplayPort") || className.contains("DP") {
                            return .displayPort
                        } else if className.contains("HDMI") {
                            return .hdmi
                        } else if className.contains("Thunderbolt") || className.contains("TB") {
                            return .thunderbolt
                        } else if className.contains("USB") {
                            return .usbc
                        }
                    }
                }

                // Check IOFBDependentID or IOFBDependentIndex for connection hints
                let pathRef = IORegistryEntrySearchCFProperty(
                    service,
                    kIOServicePlane,
                    "IODisplayPrefsKey" as CFString,
                    kCFAllocatorDefault,
                    IOOptionBits(kIORegistryIterateRecursively)
                )
                if let pathString = pathRef as? String {
                    // Parse the path for connection type hints
                    let pathLower = pathString.lowercased()
                    if pathLower.contains("displayport") || pathLower.contains("dp") {
                        return .displayPort
                    } else if pathLower.contains("hdmi") {
                        return .hdmi
                    } else if pathLower.contains("thunderbolt") || pathLower.contains("tb") {
                        return .thunderbolt
                    } else if pathLower.contains("usb") {
                        return .usbc
                    }
                }
            }
        }

        return .unknown
    }

    private func connectionTypeFromIOKit(_ type: UInt32) -> Display.ConnectionType {
        // IOKit connector type constants (from IOGraphicsTypes.h)
        // These values may vary by macOS version
        switch type {
        case 0x00000002: // kIODisplayPortConnection
            return .displayPort
        case 0x00000800: // kIODisplayHDMI
            return .hdmi
        case 0x00000004: // kIODisplayDVID
            return .dvi
        case 0x00000001: // kIODisplayVGA
            return .vga
        case 0x00000080: // Thunderbolt
            return .thunderbolt
        case 0x00000400: // USB-C
            return .usbc
        default:
            return .unknown
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let displaysDidChange = Notification.Name("displaysDidChange")
}
