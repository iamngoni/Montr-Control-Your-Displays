import CoreGraphics
import Foundation
import IOKit
import IOKit.i2c

// MARK: - IOKit I2C Bindings

// IOKit I2C interface types
private let kIOI2CNoTransactionType: UInt32 = 0
private let kIOI2CSimpleTransactionType: UInt32 = 1
private let kIOI2CDDCciReplyTransactionType: UInt32 = 2
private let kIOI2CCombinedTransactionType: UInt32 = 3

// DDC/CI Constants
private let kDDCAddress: UInt32 = 0x37
private let kDDCHostAddress: UInt8 = 0x51
private let kDDCDisplayAddress: UInt8 = 0x6E

// IOKit function declarations for I2C (Intel)
@_silgen_name("IOFBGetI2CInterfaceCount")
private func IOFBGetI2CInterfaceCount(
    _ service: io_service_t, _ count: UnsafeMutablePointer<IOItemCount>
) -> kern_return_t

@_silgen_name("IOFBCopyI2CInterfaceForBus")
private func IOFBCopyI2CInterfaceForBus(
    _ service: io_service_t, _ bus: IOOptionBits, _ interface: UnsafeMutablePointer<io_service_t>
) -> kern_return_t

// MARK: - IOAVService Bindings (Apple Silicon)
// These APIs are used on M1/M2/M3 Macs where IOFramebuffer doesn't provide I2C access

/// Opaque type for IOAVService reference
typealias IOAVServiceRef = UnsafeMutableRawPointer

/// Create an IOAVService for the default display (single-display setup)
@_silgen_name("IOAVServiceCreate")
private func IOAVServiceCreate(_ allocator: CFAllocator?) -> IOAVServiceRef?

/// Create an IOAVService for a specific display by matching criteria
@_silgen_name("IOAVServiceCreateWithService")
private func IOAVServiceCreateWithService(_ allocator: CFAllocator?, _ service: io_service_t)
    -> IOAVServiceRef?

/// Read I2C data from display via IOAVService
/// - Parameters:
///   - service: The IOAVService reference
///   - chipAddress: DDC chip address (0x37 for monitors)
///   - dataAddress: Sub-address/register (0x51 for DDC host)
///   - outputBuffer: Buffer to receive response data
///   - outputBufferSize: Size of output buffer
/// - Returns: kIOReturnSuccess on success
@_silgen_name("IOAVServiceReadI2C")
private func IOAVServiceReadI2C(
    _ service: IOAVServiceRef,
    _ chipAddress: UInt32,
    _ dataAddress: UInt32,
    _ outputBuffer: UnsafeMutablePointer<UInt8>,
    _ outputBufferSize: UInt32
) -> IOReturn

/// Write I2C data to display via IOAVService
/// - Parameters:
///   - service: The IOAVService reference
///   - chipAddress: DDC chip address (0x37 for monitors)
///   - dataAddress: Sub-address/register (0x51 for DDC host)
///   - inputBuffer: Data to write
///   - inputBufferSize: Size of input data
/// - Returns: kIOReturnSuccess on success
@_silgen_name("IOAVServiceWriteI2C")
private func IOAVServiceWriteI2C(
    _ service: IOAVServiceRef,
    _ chipAddress: UInt32,
    _ dataAddress: UInt32,
    _ inputBuffer: UnsafePointer<UInt8>,
    _ inputBufferSize: UInt32
) -> IOReturn

/// Service for DDC/CI communication with external monitors
final class DDCService {
    // MARK: - Debug Logging

    /// Enable verbose DDC debug logging (disabled in release builds by default)
    #if DEBUG
        static var debugLoggingEnabled = true
    #else
        static var debugLoggingEnabled = false
    #endif

    /// Log a debug message (only when debugLoggingEnabled is true)
    static func debugLog(_ message: String) {
        if debugLoggingEnabled {
            print(message)
        }
    }

    // MARK: - VCP Codes

    enum VCPCode: UInt8 {
        case brightness = 0x10
        case contrast = 0x12
        case colorPreset = 0x14
        case redGain = 0x16
        case greenGain = 0x18
        case blueGain = 0x1A
        case volume = 0x62
        case mute = 0x8D
        case powerMode = 0xD6
    }

    // MARK: - Errors

    enum DDCError: Error, LocalizedError {
        case displayNotFound
        case framebufferNotFound
        case i2cNotSupported
        case communicationFailed
        case invalidResponse
        case timeout

        var errorDescription: String? {
            switch self {
            case .displayNotFound: return "Display not found"
            case .framebufferNotFound: return "Framebuffer not found"
            case .i2cNotSupported: return "I2C not supported on this display"
            case .communicationFailed: return "DDC communication failed"
            case .invalidResponse: return "Invalid DDC response"
            case .timeout: return "DDC command timed out"
            }
        }
    }

    // MARK: - Singleton

    static let shared = DDCService()
    private init() {}

    // MARK: - Architecture Detection

    /// Check if running on Apple Silicon (arm64)
    static let isAppleSilicon: Bool = {
        #if arch(arm64)
            return true
        #else
            return false
        #endif
    }()

    // MARK: - DDC Approach Tracking

    /// Tracks which DDC approach works for each display
    enum DDCApproach {
        case ioavService       // Apple Silicon: IOAVService (preferred for M1/M2/M3)
        case alternativeI2C    // IODisplayConnect → IOI2CInterface recursive search
        case framebufferI2C    // Intel: IOFramebuffer → IOFBCopyI2CInterfaceForBus
        case none              // DDC not supported
    }

    /// Maps display ID to the DDC approach that works for it
    private var displayApproach: [CGDirectDisplayID: DDCApproach] = [:]

    /// IOAVService references for Apple Silicon displays (cached for performance)
    private var avServiceCache: [CGDirectDisplayID: IOAVServiceRef] = [:]

    // MARK: - DDC Support Cache

    private var ddcSupportCache: [CGDirectDisplayID: Bool] = [:]

    // MARK: - Public Methods

    /// Check if a display supports DDC/CI
    func supportsDDC(displayId: CGDirectDisplayID) -> Bool {
        // Check cache first
        if let cached = ddcSupportCache[displayId] {
            DDCService.debugLog("DDC: Using cached result for display \(displayId): \(cached)")
            return cached
        }

        DDCService.debugLog(
            "DDC: ========== Starting DDC support check for display \(displayId) ==========")
        DDCService.debugLog("DDC: Architecture: \(DDCService.isAppleSilicon ? "Apple Silicon" : "Intel")")

        // On Apple Silicon, try IOAVService first (this is the native approach for M1/M2/M3)
        // According to Lunar's creator: "IOFramebuffer methods became useless overnight on M1"
        if DDCService.isAppleSilicon {
            if probeDDCViaIOAVService(displayId: displayId) {
                DDCService.debugLog("DDC: IOAVService approach succeeded!")
                ddcSupportCache[displayId] = true
                displayApproach[displayId] = .ioavService
                return true
            }
            DDCService.debugLog("DDC: IOAVService approach failed, trying fallback methods...")
        }

        // Try alternative approach (IODisplayConnect → recursive IOI2CInterface search)
        // This approach uses simpler I2C transaction types that work on more hardware
        if probeDDCAlternative(displayId: displayId) {
            DDCService.debugLog("DDC: Alternative approach succeeded!")
            ddcSupportCache[displayId] = true
            displayApproach[displayId] = .alternativeI2C
            usesAlternativeApproach.insert(displayId)
            return true
        }

        DDCService.debugLog("DDC: Alternative approach failed, trying framebuffer approach...")

        // Fall back to original framebuffer approach with retries (mainly for Intel)
        // DDC can be flaky, especially right after display connection
        var supported = false
        let maxRetries = 5

        for attempt in 1...maxRetries {
            do {
                let brightness = try readBrightness(displayId: displayId)
                DDCService.debugLog(
                    "DDC: SUCCESS! Read brightness (\(brightness)) for display \(displayId) on attempt \(attempt)"
                )
                supported = true
                displayApproach[displayId] = .framebufferI2C
                break
            } catch {
                DDCService.debugLog(
                    "DDC: Attempt \(attempt)/\(maxRetries) failed for display \(displayId): \(error)"
                )
                if attempt < maxRetries {
                    // Increasing delay between retries - some monitors are slow
                    let delay = 0.2 * Double(attempt)  // 0.2s, 0.4s, 0.6s, 0.8s
                    DDCService.debugLog("DDC: Waiting \(delay)s before retry...")
                    Thread.sleep(forTimeInterval: delay)
                }
            }
        }

        if !supported {
            displayApproach[displayId] = DDCApproach.none
        }

        ddcSupportCache[displayId] = supported
        DDCService.debugLog(
            "DDC: ========== DDC support check complete for display \(displayId): \(supported ? "SUPPORTED" : "NOT SUPPORTED") =========="
        )
        return supported
    }

    /// Clear DDC support cache for a display
    func clearCache(for displayId: CGDirectDisplayID) {
        ddcSupportCache.removeValue(forKey: displayId)
        displayApproach.removeValue(forKey: displayId)
        usesAlternativeApproach.remove(displayId)
        avServiceCache.removeValue(forKey: displayId)
    }

    /// Clear all DDC support cache
    func clearAllCache() {
        ddcSupportCache.removeAll()
        displayApproach.removeAll()
        usesAlternativeApproach.removeAll()
        avServiceCache.removeAll()
    }

    /// Read brightness value (0-100)
    func readBrightness(displayId: CGDirectDisplayID) throws -> Int {
        let value = try readVCPValue(displayId: displayId, code: .brightness)
        return Int(value.current)
    }

    /// Set brightness value (0-100)
    func setBrightness(displayId: CGDirectDisplayID, value: Int) throws {
        let clampedValue = UInt16(max(0, min(100, value)))
        try writeVCPValue(displayId: displayId, code: .brightness, value: clampedValue)
    }

    /// Read contrast value (0-100)
    func readContrast(displayId: CGDirectDisplayID) throws -> Int {
        let value = try readVCPValue(displayId: displayId, code: .contrast)
        return Int(value.current)
    }

    /// Set contrast value (0-100)
    func setContrast(displayId: CGDirectDisplayID, value: Int) throws {
        let clampedValue = UInt16(max(0, min(100, value)))
        try writeVCPValue(displayId: displayId, code: .contrast, value: clampedValue)
    }

    /// Read volume value (0-100)
    func readVolume(displayId: CGDirectDisplayID) throws -> Int {
        let value = try readVCPValue(displayId: displayId, code: .volume)
        return Int(value.current)
    }

    /// Set volume value (0-100)
    func setVolume(displayId: CGDirectDisplayID, value: Int) throws {
        let clampedValue = UInt16(max(0, min(100, value)))
        try writeVCPValue(displayId: displayId, code: .volume, value: clampedValue)
    }

    /// Read mute state (true = muted)
    func readMute(displayId: CGDirectDisplayID) throws -> Bool {
        let value = try readVCPValue(displayId: displayId, code: .mute)
        // DDC mute: 1 = muted, 2 = unmuted
        return value.current == 1
    }

    /// Set mute state
    func setMute(displayId: CGDirectDisplayID, muted: Bool) throws {
        // DDC mute values: 1 = muted, 2 = unmuted
        let value: UInt16 = muted ? 1 : 2
        try writeVCPValue(displayId: displayId, code: .mute, value: value)
    }

    /// Check if display supports volume control
    func supportsVolume(displayId: CGDirectDisplayID) -> Bool {
        DDCService.debugLog(
            "DDC: ========== Checking volume support for display \(displayId) ==========")

        // Try multiple times - DDC can be flaky
        let maxRetries = 5  // Increased from 3

        for attempt in 1...maxRetries {
            do {
                let volume = try readVolume(displayId: displayId)
                DDCService.debugLog(
                    "DDC: SUCCESS! Read volume (\(volume)) for display \(displayId) on attempt \(attempt) - volume SUPPORTED"
                )
                return true
            } catch {
                DDCService.debugLog(
                    "DDC: Volume attempt \(attempt)/\(maxRetries) failed for display \(displayId): \(error)"
                )
                if attempt < maxRetries {
                    let delay = 0.2 * Double(attempt)
                    DDCService.debugLog("DDC: Waiting \(delay)s before volume retry...")
                    Thread.sleep(forTimeInterval: delay)
                }
            }
        }

        DDCService.debugLog(
            "DDC: ========== Volume NOT supported for display \(displayId) after \(maxRetries) attempts =========="
        )
        return false
    }

    // MARK: - Private Methods

    private struct VCPValue {
        let current: UInt16
        let maximum: UInt16
    }

    private func readVCPValue(displayId: CGDirectDisplayID, code: VCPCode) throws -> VCPValue {
        // Route to appropriate DDC method based on what worked during detection
        let approach = displayApproach[displayId] ?? DDCApproach.none

        switch approach {
        case .ioavService:
            return try readVCPViaIOAVService(displayId: displayId, code: code)
        case .alternativeI2C:
            return try readVCPAlternative(displayId: displayId, code: code)
        case .framebufferI2C, .none:
            break  // Fall through to framebuffer approach
        }

        // Legacy check for alternative approach (backward compatibility)
        if usesAlternativeApproach.contains(displayId) {
            return try readVCPAlternative(displayId: displayId, code: code)
        }

        guard let service = getFramebufferService(for: displayId) else {
            DDCService.debugLog(
                "DDC: readVCPValue - framebuffer not found for display \(displayId)")
            throw DDCError.framebufferNotFound
        }
        defer { IOObjectRelease(service) }

        // Build DDC read command
        var request = [UInt8](repeating: 0, count: 128)
        var reply = [UInt8](repeating: 0, count: 128)

        // DDC/CI read command structure
        request[0] = 0x82  // Read command
        request[1] = 0x01  // Length
        request[2] = code.rawValue

        // Send I2C request
        guard
            sendI2CRequest(
                service: service, request: request, requestLength: 3, reply: &reply, replyLength: 12
            )
        else {
            DDCService.debugLog(
                "DDC: readVCPValue - I2C communication failed for VCP code 0x\(String(format: "%02X", code.rawValue))"
            )
            throw DDCError.communicationFailed
        }

        // Parse response
        // Expected format: result code, vcp code, type, max_high, max_low, current_high, current_low
        guard reply[0] == 0x02,  // Result code OK
            reply[2] == code.rawValue
        else {
            DDCService.debugLog(
                "DDC: readVCPValue - invalid response for VCP code 0x\(String(format: "%02X", code.rawValue)): reply[0]=0x\(String(format: "%02X", reply[0])), reply[2]=0x\(String(format: "%02X", reply[2]))"
            )
            throw DDCError.invalidResponse
        }

        let maxValue = UInt16(reply[4]) << 8 | UInt16(reply[5])
        let currentValue = UInt16(reply[6]) << 8 | UInt16(reply[7])

        // Normalize to 0-100 if max is different
        let normalizedCurrent: UInt16
        if maxValue > 0 && maxValue != 100 {
            normalizedCurrent = UInt16(Double(currentValue) / Double(maxValue) * 100)
        } else {
            normalizedCurrent = currentValue
        }

        return VCPValue(current: normalizedCurrent, maximum: maxValue)
    }

    private func writeVCPValue(displayId: CGDirectDisplayID, code: VCPCode, value: UInt16) throws {
        // Route to appropriate DDC method based on what worked during detection
        let approach = displayApproach[displayId] ?? DDCApproach.none

        switch approach {
        case .ioavService:
            try writeVCPViaIOAVService(displayId: displayId, code: code, value: value)
            return
        case .alternativeI2C:
            try writeVCPAlternative(displayId: displayId, code: code, value: value)
            return
        case .framebufferI2C, .none:
            break  // Fall through to framebuffer approach
        }

        // Legacy check for alternative approach (backward compatibility)
        if usesAlternativeApproach.contains(displayId) {
            try writeVCPAlternative(displayId: displayId, code: code, value: value)
            return
        }

        guard let service = getFramebufferService(for: displayId) else {
            throw DDCError.framebufferNotFound
        }
        defer { IOObjectRelease(service) }

        // Build DDC write command
        var request = [UInt8](repeating: 0, count: 128)

        // DDC/CI write command structure
        request[0] = 0x84  // Write command
        request[1] = 0x03  // Length
        request[2] = code.rawValue
        request[3] = UInt8((value >> 8) & 0xFF)  // High byte
        request[4] = UInt8(value & 0xFF)  // Low byte

        // Add checksum
        var checksum: UInt8 = 0x6E ^ 0x51  // DDC destination ^ source
        for i in 0..<5 {
            checksum ^= request[i]
        }
        request[5] = checksum

        var reply = [UInt8](repeating: 0, count: 128)

        guard
            sendI2CRequest(
                service: service, request: request, requestLength: 6, reply: &reply, replyLength: 0)
        else {
            throw DDCError.communicationFailed
        }
    }

    // MARK: - Alternative DDC Approach (IODisplayConnect → IOI2CInterface)

    /// Find IODisplayConnect service that matches the display ID by vendor/model/serial
    private func getIODisplayConnect(for displayId: CGDirectDisplayID) -> io_service_t? {
        let targetVendor = CGDisplayVendorNumber(displayId)
        let targetModel = CGDisplayModelNumber(displayId)
        let targetSerial = CGDisplaySerialNumber(displayId)

        DDCService.debugLog(
            "DDC: [Alt] Looking for IODisplayConnect for display \(displayId) (vendor: \(String(format: "0x%04X", targetVendor)), model: \(targetModel), serial: \(targetSerial))"
        )

        let matching = IOServiceMatching("IODisplayConnect")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS
        else {
            DDCService.debugLog("DDC: [Alt] Failed to get IODisplayConnect services")
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            // Get display info from IODisplayCreateInfoDictionary
            let info =
                IODisplayCreateInfoDictionary(service, IOOptionBits(kIODisplayOnlyPreferredName))
                .takeRetainedValue() as NSDictionary

            let vendorId = (info[kDisplayVendorID] as? UInt32) ?? 0
            let productId = (info[kDisplayProductID] as? UInt32) ?? 0
            let serialNum = (info[kDisplaySerialNumber] as? UInt32) ?? 0

            DDCService.debugLog(
                "DDC: [Alt] Checking IODisplayConnect - vendor: \(String(format: "0x%04X", vendorId)), product: \(productId), serial: \(serialNum)"
            )

            // Match vendor and model, serial can be 0 on either side
            if vendorId == targetVendor && productId == targetModel {
                if serialNum == targetSerial || targetSerial == 0 || serialNum == 0 {
                    DDCService.debugLog("DDC: [Alt] Found matching IODisplayConnect!")
                    IOObjectRetain(service)
                    return service
                }
            }

            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }

        DDCService.debugLog("DDC: [Alt] No matching IODisplayConnect found")
        return nil
    }

    /// Walk up from IODisplayConnect to find the parent IOFramebuffer
    private func getFramebufferFromDisplayConnect(_ displayConnect: io_service_t) -> io_service_t? {
        var current = displayConnect
        IOObjectRetain(current)

        while true {
            if IOObjectConformsTo(current, "IOFramebuffer") != 0 {
                DDCService.debugLog("DDC: [Alt] Found IOFramebuffer parent")
                return current
            }

            var parent: io_service_t = 0
            if IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) != KERN_SUCCESS
                || parent == 0
            {
                IOObjectRelease(current)
                DDCService.debugLog("DDC: [Alt] Failed to find IOFramebuffer parent")
                return nil
            }

            IOObjectRelease(current)
            current = parent
        }
    }

    /// Recursively find first IOI2CInterface under a service
    private func findI2CInterface(under service: io_service_t) -> io_service_t? {
        var iterator: io_iterator_t = 0
        guard
            IORegistryEntryCreateIterator(
                service,
                kIOServicePlane,
                IOOptionBits(kIORegistryIterateRecursively),
                &iterator
            ) == KERN_SUCCESS
        else {
            DDCService.debugLog("DDC: [Alt] Failed to create recursive iterator")
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var obj = IOIteratorNext(iterator)
        while obj != 0 {
            if IOObjectConformsTo(obj, "IOI2CInterface") != 0 {
                DDCService.debugLog("DDC: [Alt] Found IOI2CInterface via recursive search")
                return obj  // Already retained by iterator
            }
            IOObjectRelease(obj)
            obj = IOIteratorNext(iterator)
        }

        DDCService.debugLog("DDC: [Alt] No IOI2CInterface found via recursive search")
        return nil
    }

    /// Get I2C interface for a display using alternative approach
    private func getI2CInterfaceAlternative(for displayId: CGDirectDisplayID) -> io_service_t? {
        // Step 1: Find the IODisplayConnect for this display
        guard let displayConnect = getIODisplayConnect(for: displayId) else {
            return nil
        }
        defer { IOObjectRelease(displayConnect) }

        // Step 2: Walk up to the framebuffer
        guard let framebuffer = getFramebufferFromDisplayConnect(displayConnect) else {
            return nil
        }
        defer { IOObjectRelease(framebuffer) }

        // Step 3: Find IOI2CInterface recursively under framebuffer
        return findI2CInterface(under: framebuffer)
    }

    /// Probe DDC support using alternative approach (IODisplayConnect → recursive IOI2CInterface search)
    private func probeDDCAlternative(displayId: CGDirectDisplayID) -> Bool {
        DDCService.debugLog("DDC: [Alt] ========== Probing DDC via alternative approach ==========")

        guard let i2cInterface = getI2CInterfaceAlternative(for: displayId) else {
            DDCService.debugLog("DDC: [Alt] Failed to get I2C interface")
            return false
        }
        defer { IOObjectRelease(i2cInterface) }

        // Open I2C interface
        var connect: IOI2CConnectRef?
        guard IOI2CInterfaceOpen(i2cInterface, 0, &connect) == KERN_SUCCESS,
            let i2cConnect = connect
        else {
            DDCService.debugLog("DDC: [Alt] Failed to open I2C interface")
            return false
        }
        defer { IOI2CInterfaceClose(i2cConnect, 0) }

        // Build DDC/CI "Get VCP Feature" request for brightness (0x10)
        // Using 7-bit address 0x37, simple transaction type
        let vcpCode: UInt8 = 0x10  // Brightness

        // DDC/CI packet: [host addr, length | 0x80, Get VCP opcode, VCP code, ..., checksum]
        var msg: [UInt8] = [0x51, 0x82, 0x01, vcpCode, 0x00, 0x00, 0x00]

        // Calculate checksum: XOR of write address (0x6E) and all bytes except last
        var checksum: UInt8 = 0x6E
        for i in 0..<(msg.count - 1) {
            checksum ^= msg[i]
        }
        msg[msg.count - 1] = checksum

        var reply = [UInt8](repeating: 0, count: 16)

        // Allocate stable buffers
        let sendBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: msg.count)
        let replyBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: reply.count)
        defer {
            sendBuffer.deallocate()
            replyBuffer.deallocate()
        }

        for i in 0..<msg.count {
            sendBuffer[i] = msg[i]
        }
        replyBuffer.initialize(repeating: 0, count: reply.count)

        // Build I2C request with 7-bit address and simple transaction type
        var request = IOI2CRequest()
        request.commFlags = 0
        request.sendAddress = 0x37  // 7-bit DDC address
        request.sendSubAddress = 0
        request.sendTransactionType = kIOI2CSimpleTransactionType
        request.sendBuffer = vm_address_t(bitPattern: sendBuffer)
        request.sendBytes = UInt32(msg.count)

        request.replyAddress = 0x37  // 7-bit DDC address
        request.replySubAddress = 0
        request.replyTransactionType = kIOI2CSimpleTransactionType
        request.replyBuffer = vm_address_t(bitPattern: replyBuffer)
        request.replyBytes = UInt32(reply.count)

        request.minReplyDelay = 50 * 1000 * 1000  // 50ms in nanoseconds

        let result = IOI2CSendRequest(i2cConnect, 0, &request)

        guard result == KERN_SUCCESS else {
            DDCService.debugLog("DDC: [Alt] IOI2CSendRequest failed: \(result)")
            return false
        }

        guard request.result == KERN_SUCCESS else {
            DDCService.debugLog("DDC: [Alt] I2C transaction failed: \(request.result)")
            return false
        }

        // Copy reply
        for i in 0..<Int(request.replyBytes) {
            reply[i] = replyBuffer[i]
        }

        let replyStr = reply.prefix(Int(request.replyBytes)).map { String(format: "%02X", $0) }
            .joined(separator: " ")
        DDCService.debugLog("DDC: [Alt] Reply (\(request.replyBytes) bytes): \(replyStr)")

        // Check for VCP Feature Reply marker (0x02)
        let supported = reply.contains(0x02)
        DDCService.debugLog(
            "DDC: [Alt] DDC probe result: \(supported ? "SUPPORTED" : "NOT SUPPORTED")")
        return supported
    }

    /// Read VCP value using alternative I2C approach
    private func readVCPAlternative(displayId: CGDirectDisplayID, code: VCPCode) throws -> VCPValue
    {
        guard let i2cInterface = getI2CInterfaceAlternative(for: displayId) else {
            throw DDCError.i2cNotSupported
        }
        defer { IOObjectRelease(i2cInterface) }

        var connect: IOI2CConnectRef?
        guard IOI2CInterfaceOpen(i2cInterface, 0, &connect) == KERN_SUCCESS,
            let i2cConnect = connect
        else {
            throw DDCError.communicationFailed
        }
        defer { IOI2CInterfaceClose(i2cConnect, 0) }

        // DDC/CI Get VCP Feature request
        var msg: [UInt8] = [0x51, 0x82, 0x01, code.rawValue, 0x00, 0x00, 0x00]
        var checksum: UInt8 = 0x6E
        for i in 0..<(msg.count - 1) {
            checksum ^= msg[i]
        }
        msg[msg.count - 1] = checksum

        var reply = [UInt8](repeating: 0, count: 16)

        let sendBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: msg.count)
        let replyBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: reply.count)
        defer {
            sendBuffer.deallocate()
            replyBuffer.deallocate()
        }

        for i in 0..<msg.count { sendBuffer[i] = msg[i] }
        replyBuffer.initialize(repeating: 0, count: reply.count)

        var request = IOI2CRequest()
        request.commFlags = 0
        request.sendAddress = 0x37
        request.sendSubAddress = 0
        request.sendTransactionType = kIOI2CSimpleTransactionType
        request.sendBuffer = vm_address_t(bitPattern: sendBuffer)
        request.sendBytes = UInt32(msg.count)
        request.replyAddress = 0x37
        request.replySubAddress = 0
        request.replyTransactionType = kIOI2CSimpleTransactionType
        request.replyBuffer = vm_address_t(bitPattern: replyBuffer)
        request.replyBytes = UInt32(reply.count)
        request.minReplyDelay = 50 * 1000 * 1000

        guard IOI2CSendRequest(i2cConnect, 0, &request) == KERN_SUCCESS,
            request.result == KERN_SUCCESS
        else {
            throw DDCError.communicationFailed
        }

        for i in 0..<Int(request.replyBytes) { reply[i] = replyBuffer[i] }

        // Parse reply - look for VCP reply marker (0x02) and extract values
        // Reply format varies, but typically: [source, length, 0x02, result, vcp_code, type, max_h, max_l, cur_h, cur_l, checksum]
        guard let markerIndex = reply.firstIndex(of: 0x02),
            markerIndex + 7 < reply.count
        else {
            throw DDCError.invalidResponse
        }

        let maxValue = UInt16(reply[markerIndex + 4]) << 8 | UInt16(reply[markerIndex + 5])
        let currentValue = UInt16(reply[markerIndex + 6]) << 8 | UInt16(reply[markerIndex + 7])

        let normalizedCurrent: UInt16
        if maxValue > 0 && maxValue != 100 {
            normalizedCurrent = UInt16(Double(currentValue) / Double(maxValue) * 100)
        } else {
            normalizedCurrent = currentValue
        }

        return VCPValue(current: normalizedCurrent, maximum: maxValue)
    }

    /// Write VCP value using alternative I2C approach
    private func writeVCPAlternative(displayId: CGDirectDisplayID, code: VCPCode, value: UInt16)
        throws
    {
        guard let i2cInterface = getI2CInterfaceAlternative(for: displayId) else {
            throw DDCError.i2cNotSupported
        }
        defer { IOObjectRelease(i2cInterface) }

        var connect: IOI2CConnectRef?
        guard IOI2CInterfaceOpen(i2cInterface, 0, &connect) == KERN_SUCCESS,
            let i2cConnect = connect
        else {
            throw DDCError.communicationFailed
        }
        defer { IOI2CInterfaceClose(i2cConnect, 0) }

        // DDC/CI Set VCP Feature: [host addr, length | 0x80, Set VCP opcode (0x03), vcp code, value_h, value_l, checksum]
        var msg: [UInt8] = [
            0x51, 0x84, 0x03, code.rawValue, UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF), 0x00,
        ]
        var checksum: UInt8 = 0x6E
        for i in 0..<(msg.count - 1) {
            checksum ^= msg[i]
        }
        msg[msg.count - 1] = checksum

        let sendBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: msg.count)
        defer { sendBuffer.deallocate() }

        for i in 0..<msg.count { sendBuffer[i] = msg[i] }

        var request = IOI2CRequest()
        request.commFlags = 0
        request.sendAddress = 0x37
        request.sendSubAddress = 0
        request.sendTransactionType = kIOI2CSimpleTransactionType
        request.sendBuffer = vm_address_t(bitPattern: sendBuffer)
        request.sendBytes = UInt32(msg.count)
        request.replyTransactionType = kIOI2CNoTransactionType
        request.replyBytes = 0

        guard IOI2CSendRequest(i2cConnect, 0, &request) == KERN_SUCCESS,
            request.result == KERN_SUCCESS
        else {
            throw DDCError.communicationFailed
        }
    }

    // MARK: - IOAVService DDC Approach (Apple Silicon)

    /// Get or create IOAVService for a display
    /// On Apple Silicon, IOAVService is the native way to communicate with displays via I2C/DDC
    private func getIOAVServiceForDisplay(_ displayId: CGDirectDisplayID) -> IOAVServiceRef? {
        // Check cache first
        if let cached = avServiceCache[displayId] {
            return cached
        }

        DDCService.debugLog("DDC: [AVService] Getting IOAVService for display \(displayId)")

        // For single display setups, IOAVServiceCreate() works directly
        // For multi-display (especially Mac Mini), we need to find the specific AppleCLCD2 service

        // First, try to find the specific service by matching display attributes
        if let service = findAppleCLCD2Service(for: displayId) {
            if let avService = IOAVServiceCreateWithService(kCFAllocatorDefault, service) {
                DDCService.debugLog("DDC: [AVService] Created IOAVService from AppleCLCD2 match")
                IOObjectRelease(service)
                avServiceCache[displayId] = avService
                return avService
            }
            IOObjectRelease(service)
        }

        // Fallback: Try generic IOAVServiceCreate for single-display setups
        if let avService = IOAVServiceCreate(kCFAllocatorDefault) {
            DDCService.debugLog("DDC: [AVService] Created generic IOAVService")
            avServiceCache[displayId] = avService
            return avService
        }

        DDCService.debugLog("DDC: [AVService] Failed to create IOAVService")
        return nil
    }

    /// Find AppleCLCD2 service matching a display (for multi-display Mac Mini setups)
    /// AppleCLCD2 is the display controller class on Apple Silicon
    private func findAppleCLCD2Service(for displayId: CGDirectDisplayID) -> io_service_t? {
        let targetVendor = CGDisplayVendorNumber(displayId)
        let targetModel = CGDisplayModelNumber(displayId)
        let targetSerial = CGDisplaySerialNumber(displayId)

        DDCService.debugLog(
            "DDC: [AVService] Looking for AppleCLCD2 for display \(displayId) (vendor: \(String(format: "0x%04X", targetVendor)), model: \(targetModel), serial: \(targetSerial))"
        )

        // Search for AppleCLCD2 services (Apple Silicon display controllers)
        let matching = IOServiceMatching("AppleCLCD2")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS
        else {
            DDCService.debugLog("DDC: [AVService] No AppleCLCD2 services found")
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            // Walk down to find IODisplayConnect child with matching EDID info
            if let displayConnect = findDisplayConnect(under: service, vendor: targetVendor,
                model: targetModel, serial: targetSerial)
            {
                IOObjectRelease(displayConnect)
                DDCService.debugLog("DDC: [AVService] Found matching AppleCLCD2!")
                return service
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }

        DDCService.debugLog("DDC: [AVService] No matching AppleCLCD2 found")
        return nil
    }

    /// Find IODisplayConnect child matching display attributes
    private func findDisplayConnect(
        under service: io_service_t, vendor: UInt32, model: UInt32, serial: UInt32
    ) -> io_service_t? {
        var iterator: io_iterator_t = 0
        guard
            IORegistryEntryCreateIterator(
                service, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator
            ) == KERN_SUCCESS
        else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var child = IOIteratorNext(iterator)
        while child != 0 {
            if IOObjectConformsTo(child, "IODisplayConnect") != 0 {
                // Get display info dictionary
                let info = IODisplayCreateInfoDictionary(
                    child, IOOptionBits(kIODisplayOnlyPreferredName)
                ).takeRetainedValue() as NSDictionary

                let vendorId = (info[kDisplayVendorID] as? UInt32) ?? 0
                let productId = (info[kDisplayProductID] as? UInt32) ?? 0
                let serialNum = (info[kDisplaySerialNumber] as? UInt32) ?? 0

                DDCService.debugLog(
                    "DDC: [AVService] Checking IODisplayConnect - vendor: \(String(format: "0x%04X", vendorId)), product: \(productId), serial: \(serialNum)"
                )

                if vendorId == vendor && productId == model {
                    if serialNum == serial || serial == 0 || serialNum == 0 {
                        return child
                    }
                }
            }
            IOObjectRelease(child)
            child = IOIteratorNext(iterator)
        }
        return nil
    }

    /// Probe DDC support using IOAVService (Apple Silicon native approach)
    private func probeDDCViaIOAVService(displayId: CGDirectDisplayID) -> Bool {
        DDCService.debugLog(
            "DDC: [AVService] ========== Probing DDC via IOAVService for display \(displayId) =========="
        )

        // Note: Mac Mini HDMI ports reportedly don't support DDC on Apple Silicon
        // See: https://alinpanaitiu.com/blog/journey-to-ddc-on-m1-macs/
        // If DDC fails on an HDMI connection, this is likely the cause.

        guard let avService = getIOAVServiceForDisplay(displayId) else {
            DDCService.debugLog("DDC: [AVService] Failed to get IOAVService")
            DDCService.debugLog("DDC: [AVService] Note: If this is a Mac Mini with HDMI, DDC is not supported on HDMI ports")
            return false
        }

        // Try to read brightness (VCP 0x10) as a DDC capability test
        // Build DDC/CI Get VCP Feature request
        var data: [UInt8] = [0x82, 0x01, 0x10, 0x00, 0x00, 0x00]
        // Checksum: XOR of all bytes including addresses (0x6E ^ 0x51 ^ payload bytes)
        var checksum: UInt8 = 0x6E ^ 0x51
        for i in 0..<3 {
            checksum ^= data[i]
        }
        data[3] = checksum

        // Try write + read to verify DDC works
        let writeResult = IOAVServiceWriteI2C(avService, 0x37, 0x51, &data, 4)

        if writeResult != kIOReturnSuccess {
            DDCService.debugLog(
                "DDC: [AVService] Write failed with result: \(String(format: "0x%08X", writeResult))")
            return false
        }

        // Small delay for DDC response (monitors need time to process)
        usleep(50000)  // 50ms

        // Read response
        var reply = [UInt8](repeating: 0, count: 12)
        let readResult = IOAVServiceReadI2C(avService, 0x37, 0x51, &reply, 12)

        if readResult != kIOReturnSuccess {
            DDCService.debugLog(
                "DDC: [AVService] Read failed with result: \(String(format: "0x%08X", readResult))")
            // Note: Reads fail ~30% on Apple Silicon according to Lunar's creator
            // But if write succeeded, DDC likely works - try write-only mode
            DDCService.debugLog("DDC: [AVService] Write succeeded but read failed - DDC may still work (write-only)")
            return true  // Consider DDC supported if write works
        }

        let replyStr = reply.map { String(format: "%02X", $0) }.joined(separator: " ")
        DDCService.debugLog("DDC: [AVService] Reply: \(replyStr)")

        // Check for VCP reply marker (0x02 indicates successful VCP response)
        let supported = reply.contains(0x02)
        DDCService.debugLog(
            "DDC: [AVService] DDC probe result: \(supported ? "SUPPORTED" : "NOT SUPPORTED")")
        return supported
    }

    /// Read VCP value using IOAVService (Apple Silicon)
    private func readVCPViaIOAVService(displayId: CGDirectDisplayID, code: VCPCode) throws
        -> VCPValue
    {
        guard let avService = getIOAVServiceForDisplay(displayId) else {
            throw DDCError.i2cNotSupported
        }

        // Build DDC/CI Get VCP Feature request
        // Format: [length | 0x80, Get VCP opcode (0x01), VCP code, checksum]
        var data: [UInt8] = [0x82, 0x01, code.rawValue, 0x00, 0x00, 0x00]
        var checksum: UInt8 = 0x6E ^ 0x51
        for i in 0..<3 {
            checksum ^= data[i]
        }
        data[3] = checksum

        let writeResult = IOAVServiceWriteI2C(avService, 0x37, 0x51, &data, 4)
        guard writeResult == kIOReturnSuccess else {
            DDCService.debugLog(
                "DDC: [AVService] readVCP write failed: \(String(format: "0x%08X", writeResult))")
            throw DDCError.communicationFailed
        }

        usleep(50000)  // 50ms delay

        var reply = [UInt8](repeating: 0, count: 12)
        let readResult = IOAVServiceReadI2C(avService, 0x37, 0x51, &reply, 12)
        guard readResult == kIOReturnSuccess else {
            DDCService.debugLog(
                "DDC: [AVService] readVCP read failed: \(String(format: "0x%08X", readResult))")
            throw DDCError.communicationFailed
        }

        // Parse VCP reply
        // Format: [source, length, 0x02 (reply marker), result, vcp_code, type, max_h, max_l, cur_h, cur_l, checksum]
        guard let markerIndex = reply.firstIndex(of: 0x02), markerIndex + 7 < reply.count else {
            throw DDCError.invalidResponse
        }

        let maxValue = UInt16(reply[markerIndex + 4]) << 8 | UInt16(reply[markerIndex + 5])
        let currentValue = UInt16(reply[markerIndex + 6]) << 8 | UInt16(reply[markerIndex + 7])

        let normalizedCurrent: UInt16
        if maxValue > 0 && maxValue != 100 {
            normalizedCurrent = UInt16(Double(currentValue) / Double(maxValue) * 100)
        } else {
            normalizedCurrent = currentValue
        }

        return VCPValue(current: normalizedCurrent, maximum: maxValue)
    }

    /// Write VCP value using IOAVService (Apple Silicon)
    private func writeVCPViaIOAVService(displayId: CGDirectDisplayID, code: VCPCode, value: UInt16)
        throws
    {
        guard let avService = getIOAVServiceForDisplay(displayId) else {
            throw DDCError.i2cNotSupported
        }

        // Build DDC/CI Set VCP Feature command
        // Format: [length | 0x80, Set VCP opcode (0x03), VCP code, value_h, value_l, checksum]
        var data: [UInt8] = [
            0x84,  // Length (4 bytes) | 0x80
            0x03,  // Set VCP opcode
            code.rawValue,
            UInt8((value >> 8) & 0xFF),  // High byte
            UInt8(value & 0xFF),  // Low byte
            0x00,  // Checksum placeholder
        ]

        // Calculate checksum: XOR of addresses and data
        var checksum: UInt8 = 0x6E ^ 0x51
        for i in 0..<5 {
            checksum ^= data[i]
        }
        data[5] = checksum

        let result = IOAVServiceWriteI2C(avService, 0x37, 0x51, &data, 6)
        guard result == kIOReturnSuccess else {
            DDCService.debugLog(
                "DDC: [AVService] writeVCP failed: \(String(format: "0x%08X", result))")
            throw DDCError.communicationFailed
        }

        DDCService.debugLog(
            "DDC: [AVService] Successfully set VCP 0x\(String(format: "%02X", code.rawValue)) = \(value)"
        )
    }

    /// Track which displays use the alternative approach
    private var usesAlternativeApproach: Set<CGDirectDisplayID> = []

    /// Mark a display as using the alternative approach
    func setUsesAlternativeApproach(_ displayId: CGDirectDisplayID, _ uses: Bool) {
        if uses {
            usesAlternativeApproach.insert(displayId)
        } else {
            usesAlternativeApproach.remove(displayId)
        }
    }

    /// Get all framebuffer services that have I2C support
    private func getAllI2CFramebuffers() -> [io_service_t] {
        var framebuffers: [io_service_t] = []
        var iterator: io_iterator_t = 0

        let matching = IOServiceMatching("IOFramebuffer")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS
        else {
            DDCService.debugLog("DDC: Failed to get IOFramebuffer services")
            return framebuffers
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            var busCount: IOItemCount = 0
            if IOFBGetI2CInterfaceCount(service, &busCount) == KERN_SUCCESS && busCount > 0 {
                DDCService.debugLog("DDC: Found framebuffer with \(busCount) I2C bus(es)")
                framebuffers.append(service)
            } else {
                IOObjectRelease(service)
            }
            service = IOIteratorNext(iterator)
        }

        DDCService.debugLog("DDC: Found \(framebuffers.count) framebuffer(s) with I2C support")
        return framebuffers
    }

    private func getFramebufferService(for displayId: CGDirectDisplayID) -> io_service_t? {
        // Get the display's vendor and model IDs for matching
        let targetVendor = CGDisplayVendorNumber(displayId)
        let targetModel = CGDisplayModelNumber(displayId)
        let targetSerial = CGDisplaySerialNumber(displayId)

        DDCService.debugLog(
            "DDC: Looking for framebuffer for display \(displayId) (vendor: \(String(format: "0x%04X", targetVendor)), model: \(targetModel), serial: \(targetSerial))"
        )

        // Get all framebuffers with I2C support
        let framebuffers = getAllI2CFramebuffers()

        if framebuffers.isEmpty {
            DDCService.debugLog("DDC: No framebuffers with I2C support found")
            return nil
        }

        // Try to find an exact match first
        var bestMatch: io_service_t = 0
        var foundExactMatch = false

        for service in framebuffers {
            // Try to find IODisplayConnect child to get display info
            var displayIterator: io_iterator_t = 0
            if IORegistryEntryGetChildIterator(service, kIOServicePlane, &displayIterator)
                == KERN_SUCCESS
            {
                defer { IOObjectRelease(displayIterator) }

                var displayService = IOIteratorNext(displayIterator)
                while displayService != 0 {
                    defer {
                        IOObjectRelease(displayService)
                        displayService = IOIteratorNext(displayIterator)
                    }

                    // Check for DisplayVendorID and DisplayProductID
                    var vendorId: UInt32 = 0
                    var productId: UInt32 = 0
                    var serialNum: UInt32 = 0

                    if let vendorRef = IORegistryEntryCreateCFProperty(
                        displayService, "DisplayVendorID" as CFString, kCFAllocatorDefault, 0)
                    {
                        if let num = vendorRef.takeRetainedValue() as? NSNumber {
                            vendorId = num.uint32Value
                        }
                    }

                    if let productRef = IORegistryEntryCreateCFProperty(
                        displayService, "DisplayProductID" as CFString, kCFAllocatorDefault, 0)
                    {
                        if let num = productRef.takeRetainedValue() as? NSNumber {
                            productId = num.uint32Value
                        }
                    }

                    if let serialRef = IORegistryEntryCreateCFProperty(
                        displayService, "DisplaySerialNumber" as CFString, kCFAllocatorDefault, 0)
                    {
                        if let num = serialRef.takeRetainedValue() as? NSNumber {
                            serialNum = num.uint32Value
                        }
                    }

                    DDCService.debugLog(
                        "DDC: Checking framebuffer child - vendor: \(String(format: "0x%04X", vendorId)), product: \(productId), serial: \(serialNum)"
                    )

                    // Check if this matches our target display
                    if vendorId == targetVendor && productId == targetModel {
                        // Exact match: serials match exactly, OR target accepts any serial (targetSerial == 0)
                        if serialNum == targetSerial || targetSerial == 0 {
                            DDCService.debugLog("DDC: Found exact framebuffer match!")
                            bestMatch = service
                            foundExactMatch = true
                            break
                        } else if serialNum == 0 && !foundExactMatch {
                            // Partial match: framebuffer has no serial but we need a specific one
                            // Keep searching for an exact match, but remember this as a fallback
                            DDCService.debugLog(
                                "DDC: Found partial framebuffer match (vendor/product, unknown serial)"
                            )
                            if bestMatch == 0 {
                                bestMatch = service
                            }
                        } else if !foundExactMatch && bestMatch == 0 {
                            // Different serial - keep as last resort fallback
                            DDCService.debugLog(
                                "DDC: Found partial framebuffer match (vendor/product, different serial)"
                            )
                            bestMatch = service
                        }
                    }
                }

                if foundExactMatch {
                    break
                }
            }
        }

        // If we found a match, retain it and release the others
        if bestMatch != 0 {
            for service in framebuffers where service != bestMatch {
                IOObjectRelease(service)
            }
            DDCService.debugLog("DDC: Using matched framebuffer service")
            return bestMatch
        }

        // No match found - on Apple Silicon with single external display, use the first framebuffer
        // This is a common fallback that works for most setups
        if framebuffers.count > 0 {
            DDCService.debugLog(
                "DDC: No exact framebuffer match found, using first available framebuffer as fallback"
            )
            // Release all but the first
            for i in 1..<framebuffers.count {
                IOObjectRelease(framebuffers[i])
            }
            return framebuffers[0]
        }

        DDCService.debugLog("DDC: No framebuffer service found")
        return nil
    }

    private func sendI2CRequest(
        service: io_service_t,
        request: [UInt8],
        requestLength: Int,
        reply: inout [UInt8],
        replyLength: Int
    ) -> Bool {
        // Get I2C interface count for this framebuffer
        var busCount: IOItemCount = 0
        guard IOFBGetI2CInterfaceCount(service, &busCount) == KERN_SUCCESS, busCount > 0 else {
            DDCService.debugLog("DDC: sendI2CRequest - no I2C interfaces found")
            return false
        }

        DDCService.debugLog("DDC: sendI2CRequest - found \(busCount) I2C bus(es)")

        // Try each I2C bus until we find one that works
        for bus in 0..<Int(busCount) {
            var i2cInterface: io_service_t = 0
            guard
                IOFBCopyI2CInterfaceForBus(service, IOOptionBits(bus), &i2cInterface)
                    == KERN_SUCCESS
            else {
                DDCService.debugLog(
                    "DDC: sendI2CRequest - failed to get I2C interface for bus \(bus)")
                continue
            }
            defer { IOObjectRelease(i2cInterface) }

            // Open the I2C interface
            var i2cConnect: IOI2CConnectRef?
            guard IOI2CInterfaceOpen(i2cInterface, 0, &i2cConnect) == KERN_SUCCESS,
                let connect = i2cConnect
            else {
                DDCService.debugLog(
                    "DDC: sendI2CRequest - failed to open I2C interface for bus \(bus)")
                continue
            }
            defer { IOI2CInterfaceClose(connect, 0) }

            // Send the DDC command
            if performDDCTransaction(
                connect: connect, request: request, requestLength: requestLength, reply: &reply,
                replyLength: replyLength)
            {
                DDCService.debugLog("DDC: sendI2CRequest - transaction succeeded on bus \(bus)")
                return true
            } else {
                DDCService.debugLog("DDC: sendI2CRequest - transaction failed on bus \(bus)")
            }
        }

        DDCService.debugLog("DDC: sendI2CRequest - all buses failed")
        return false
    }

    private func performDDCTransaction(
        connect: IOI2CConnectRef,
        request: [UInt8],
        requestLength: Int,
        reply: inout [UInt8],
        replyLength: Int
    ) -> Bool {
        // Allocate buffers that will remain valid for the entire transaction
        let sendBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 128)
        let replyBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 128)
        defer {
            sendBuffer.deallocate()
            replyBuffer.deallocate()
        }

        // Initialize buffers to zero
        sendBuffer.initialize(repeating: 0, count: 128)
        replyBuffer.initialize(repeating: 0, count: 128)

        // DDC/CI packet structure for VCP request:
        // Byte 0: 0x6E XOR 0x51 XOR (length | 0x80) XOR data...
        // The host address is 0x51, display address is 0x6E

        // Build send data
        let payloadLength = requestLength
        sendBuffer[0] = UInt8(0x80 | payloadLength)  // Length byte with command flag

        for i in 0..<requestLength {
            sendBuffer[i + 1] = request[i]
        }

        // Calculate checksum: XOR of all bytes including addresses
        var checksum: UInt8 = kDDCDisplayAddress ^ kDDCHostAddress
        for i in 0...requestLength {
            checksum ^= sendBuffer[i]
        }
        sendBuffer[requestLength + 1] = checksum

        let totalSendLength = requestLength + 2  // data + length byte + checksum

        // Prepare I2C request structure
        var i2cRequest = IOI2CRequest()
        i2cRequest.commFlags = 0
        i2cRequest.sendAddress = UInt32(kDDCDisplayAddress)
        i2cRequest.sendTransactionType = kIOI2CSimpleTransactionType
        i2cRequest.sendBuffer = vm_address_t(bitPattern: sendBuffer)
        i2cRequest.sendBytes = UInt32(totalSendLength)

        if replyLength > 0 {
            // DDC/CI reply transaction
            i2cRequest.replyAddress = UInt32(kDDCDisplayAddress) | 0x01  // Read address
            i2cRequest.replyTransactionType = kIOI2CDDCciReplyTransactionType
            i2cRequest.replyBuffer = vm_address_t(bitPattern: replyBuffer)
            i2cRequest.replyBytes = UInt32(replyLength + 3)  // Include header and checksum

            // DDC/CI requires a delay between write and read
            // Increased from 50ms to 100ms for slower monitors
            i2cRequest.minReplyDelay = 100 * 1000 * 1000  // 100ms in nanoseconds
        } else {
            i2cRequest.replyTransactionType = kIOI2CNoTransactionType
            i2cRequest.replyBytes = 0
        }

        // Send the I2C request
        let result = IOI2CSendRequest(connect, 0, &i2cRequest)
        guard result == KERN_SUCCESS else {
            DDCService.debugLog("DDC: IOI2CSendRequest failed with result: \(result)")
            return false
        }

        // Check if transaction completed successfully
        guard i2cRequest.result == KERN_SUCCESS else {
            DDCService.debugLog("DDC: I2C transaction result failed: \(i2cRequest.result)")
            return false
        }

        // Parse reply if we were expecting one
        if replyLength > 0 {
            // DDC/CI reply format:
            // [source addr | length | result code | vcp code | type | max_h | max_l | cur_h | cur_l | checksum]

            // Verify we got expected reply length
            guard i2cRequest.replyBytes >= 3 else {
                DDCService.debugLog("DDC: Reply too short: \(i2cRequest.replyBytes) bytes")
                return false
            }

            DDCService.debugLog("DDC: Got reply with \(i2cRequest.replyBytes) bytes")

            // Extract reply data (skip the length byte at position 0)
            let dataStart = 1  // After length byte
            for i in 0..<min(replyLength, Int(i2cRequest.replyBytes) - 2) {
                reply[i] = replyBuffer[dataStart + i]
            }

            // Log first few bytes for debugging
            let debugBytes = (0..<min(10, Int(i2cRequest.replyBytes))).map {
                String(format: "%02X", replyBuffer[$0])
            }.joined(separator: " ")
            DDCService.debugLog("DDC: Reply bytes: \(debugBytes)")
        }

        return true
    }
}

// MARK: - Built-in Display Brightness

extension DDCService {
    /// Get brightness for built-in display using CoreDisplay private API
    func getBuiltInBrightness(displayId: CGDirectDisplayID) -> Float? {
        // Use CoreDisplay private API
        // This is undocumented but widely used
        typealias GetBrightnessFunc = @convention(c) (UInt32) -> Float

        guard
            let coreDisplay = dlopen(
                "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY)
        else {
            return nil
        }
        defer { dlclose(coreDisplay) }

        guard let symbol = dlsym(coreDisplay, "CoreDisplay_Display_GetUserBrightness") else {
            return nil
        }

        let getBrightness = unsafeBitCast(symbol, to: GetBrightnessFunc.self)

        let targetDisplay: CGDirectDisplayID
        if CGDisplayIsBuiltin(displayId) != 0 {
            targetDisplay = displayId
        } else {
            let mainDisplay = CGMainDisplayID()
            guard CGDisplayIsBuiltin(mainDisplay) != 0 else {
                return nil
            }
            targetDisplay = mainDisplay
        }

        return getBrightness(targetDisplay)
    }

    /// Convenience getter that targets the main display (only works if it's built-in)
    func getBuiltInBrightness() -> Float? {
        getBuiltInBrightness(displayId: CGMainDisplayID())
    }

    /// Set brightness for built-in display using CoreDisplay private API
    func setBuiltInBrightness(_ brightness: Float, displayId: CGDirectDisplayID) -> Bool {
        typealias SetBrightnessFunc = @convention(c) (UInt32, Double) -> Void

        guard
            let coreDisplay = dlopen(
                "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY)
        else {
            return false
        }
        defer { dlclose(coreDisplay) }

        guard let symbol = dlsym(coreDisplay, "CoreDisplay_Display_SetUserBrightness") else {
            return false
        }

        let setBrightness = unsafeBitCast(symbol, to: SetBrightnessFunc.self)

        let targetDisplay: CGDirectDisplayID
        if CGDisplayIsBuiltin(displayId) != 0 {
            targetDisplay = displayId
        } else {
            let mainDisplay = CGMainDisplayID()
            guard CGDisplayIsBuiltin(mainDisplay) != 0 else {
                return false
            }
            targetDisplay = mainDisplay
        }

        let clampedBrightness = max(0.0, min(1.0, Double(brightness)))
        setBrightness(targetDisplay, clampedBrightness)

        return true
    }

    /// Convenience setter that targets the main display (only works if it's built-in)
    func setBuiltInBrightness(_ brightness: Float) -> Bool {
        setBuiltInBrightness(brightness, displayId: CGMainDisplayID())
    }
}
