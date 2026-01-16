import Foundation
import IOKit
import IOKit.i2c
import CoreGraphics

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

// IOKit function declarations for I2C
@_silgen_name("IOFBGetI2CInterfaceCount")
private func IOFBGetI2CInterfaceCount(_ service: io_service_t, _ count: UnsafeMutablePointer<IOItemCount>) -> kern_return_t

@_silgen_name("IOFBCopyI2CInterfaceForBus")
private func IOFBCopyI2CInterfaceForBus(_ service: io_service_t, _ bus: IOOptionBits, _ interface: UnsafeMutablePointer<io_service_t>) -> kern_return_t

/// Service for DDC/CI communication with external monitors
final class DDCService {
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

    // MARK: - DDC Support Cache

    private var ddcSupportCache: [CGDirectDisplayID: Bool] = [:]

    // MARK: - Public Methods

    /// Check if a display supports DDC/CI
    func supportsDDC(displayId: CGDirectDisplayID) -> Bool {
        // Check cache first
        if let cached = ddcSupportCache[displayId] {
            return cached
        }

        // Try to read brightness to test DDC support
        let supported: Bool
        if let _ = try? readBrightness(displayId: displayId) {
            supported = true
        } else {
            supported = false
        }

        ddcSupportCache[displayId] = supported
        return supported
    }

    /// Clear DDC support cache for a display
    func clearCache(for displayId: CGDirectDisplayID) {
        ddcSupportCache.removeValue(forKey: displayId)
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
        do {
            _ = try readVolume(displayId: displayId)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Private Methods

    private struct VCPValue {
        let current: UInt16
        let maximum: UInt16
    }

    private func readVCPValue(displayId: CGDirectDisplayID, code: VCPCode) throws -> VCPValue {
        guard let service = getFramebufferService(for: displayId) else {
            throw DDCError.framebufferNotFound
        }
        defer { IOObjectRelease(service) }

        // Build DDC read command
        var request = [UInt8](repeating: 0, count: 128)
        var reply = [UInt8](repeating: 0, count: 128)

        // DDC/CI read command structure
        request[0] = 0x82 // Read command
        request[1] = 0x01 // Length
        request[2] = code.rawValue

        // Send I2C request
        guard sendI2CRequest(service: service, request: request, requestLength: 3, reply: &reply, replyLength: 12) else {
            throw DDCError.communicationFailed
        }

        // Parse response
        // Expected format: result code, vcp code, type, max_high, max_low, current_high, current_low
        guard reply[0] == 0x02, // Result code OK
              reply[2] == code.rawValue else {
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
        guard let service = getFramebufferService(for: displayId) else {
            throw DDCError.framebufferNotFound
        }
        defer { IOObjectRelease(service) }

        // Build DDC write command
        var request = [UInt8](repeating: 0, count: 128)

        // DDC/CI write command structure
        request[0] = 0x84 // Write command
        request[1] = 0x03 // Length
        request[2] = code.rawValue
        request[3] = UInt8((value >> 8) & 0xFF) // High byte
        request[4] = UInt8(value & 0xFF) // Low byte

        // Add checksum
        var checksum: UInt8 = 0x6E ^ 0x51 // DDC destination ^ source
        for i in 0..<5 {
            checksum ^= request[i]
        }
        request[5] = checksum

        var reply = [UInt8](repeating: 0, count: 128)

        guard sendI2CRequest(service: service, request: request, requestLength: 6, reply: &reply, replyLength: 0) else {
            throw DDCError.communicationFailed
        }
    }

    private func getFramebufferService(for displayId: CGDirectDisplayID) -> io_service_t? {
        // Iterate through all framebuffers and match by vendor/product ID
        var iterator: io_iterator_t = 0

        let matching = IOServiceMatching("IOFramebuffer")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        // Get the display's vendor and model IDs for matching
        let targetVendor = CGDisplayVendorNumber(displayId)
        let targetModel = CGDisplayModelNumber(displayId)
        let targetSerial = CGDisplaySerialNumber(displayId)

        var bestMatch: io_service_t = 0
        var foundExactMatch = false

        var service = IOIteratorNext(iterator)
        while service != 0 {
            // Try to find IODisplayConnect child to get display info
            var displayIterator: io_iterator_t = 0
            if IORegistryEntryGetChildIterator(service, kIOServicePlane, &displayIterator) == KERN_SUCCESS {
                defer { IOObjectRelease(displayIterator) }

                var displayService = IOIteratorNext(displayIterator)
                while displayService != 0 {
                    // Check for DisplayVendorID and DisplayProductID
                    var vendorId: UInt32 = 0
                    var productId: UInt32 = 0
                    var serialNum: UInt32 = 0

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

                    if let serialRef = IORegistryEntryCreateCFProperty(displayService, "DisplaySerialNumber" as CFString, kCFAllocatorDefault, 0) {
                        if let num = serialRef.takeRetainedValue() as? NSNumber {
                            serialNum = num.uint32Value
                        }
                    }

                    IOObjectRelease(displayService)

                    // Check if this matches our target display
                    if vendorId == targetVendor && productId == targetModel {
                        if serialNum == targetSerial || targetSerial == 0 {
                            // Exact match found
                            if bestMatch != 0 {
                                IOObjectRelease(bestMatch)
                            }
                            bestMatch = service
                            foundExactMatch = true
                            break
                        } else if !foundExactMatch {
                            // Partial match (vendor/product but different serial)
                            if bestMatch != 0 {
                                IOObjectRelease(bestMatch)
                            }
                            bestMatch = service
                        }
                    }

                    displayService = IOIteratorNext(displayIterator)
                }
            }

            if foundExactMatch {
                break
            }

            if bestMatch != service {
                IOObjectRelease(service)
            }
            service = IOIteratorNext(iterator)
        }

        // If no match found, try the first available framebuffer (for single external display setups)
        if bestMatch == 0 {
            IOIteratorReset(iterator)
            service = IOIteratorNext(iterator)
            while service != 0 {
                // Check if this framebuffer has I2C support (indicates external display)
                var busCount: IOItemCount = 0
                if IOFBGetI2CInterfaceCount(service, &busCount) == KERN_SUCCESS && busCount > 0 {
                    return service
                }
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
        }

        return bestMatch
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
            return false
        }

        // Try each I2C bus until we find one that works
        for bus in 0..<Int(busCount) {
            var i2cInterface: io_service_t = 0
            guard IOFBCopyI2CInterfaceForBus(service, IOOptionBits(bus), &i2cInterface) == KERN_SUCCESS else {
                continue
            }
            defer { IOObjectRelease(i2cInterface) }

            // Open the I2C interface
            var i2cConnect: IOI2CConnectRef?
            guard IOI2CInterfaceOpen(i2cInterface, 0, &i2cConnect) == KERN_SUCCESS,
                  let connect = i2cConnect else {
                continue
            }
            defer { IOI2CInterfaceClose(connect, 0) }

            // Send the DDC command
            if performDDCTransaction(connect: connect, request: request, requestLength: requestLength, reply: &reply, replyLength: replyLength) {
                return true
            }
        }

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
            i2cRequest.minReplyDelay = 50 * 1000 * 1000  // 50ms in nanoseconds
        } else {
            i2cRequest.replyTransactionType = kIOI2CNoTransactionType
            i2cRequest.replyBytes = 0
        }

        // Send the I2C request
        let result = IOI2CSendRequest(connect, 0, &i2cRequest)
        guard result == KERN_SUCCESS else {
            return false
        }

        // Check if transaction completed successfully
        guard i2cRequest.result == KERN_SUCCESS else {
            return false
        }

        // Parse reply if we were expecting one
        if replyLength > 0 {
            // DDC/CI reply format:
            // [source addr | length | result code | vcp code | type | max_h | max_l | cur_h | cur_l | checksum]

            // Verify we got expected reply length
            guard i2cRequest.replyBytes >= 3 else {
                return false
            }

            // Extract reply data (skip the length byte at position 0)
            let dataStart = 1  // After length byte
            for i in 0..<min(replyLength, Int(i2cRequest.replyBytes) - 2) {
                reply[i] = replyBuffer[dataStart + i]
            }
        }

        return true
    }
}

// MARK: - Built-in Display Brightness

extension DDCService {
    /// Get brightness for built-in display using CoreDisplay private API
    func getBuiltInBrightness() -> Float? {
        // Use CoreDisplay private API
        // This is undocumented but widely used
        typealias GetBrightnessFunc = @convention(c) (UInt32) -> Float

        guard let coreDisplay = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY) else {
            return nil
        }
        defer { dlclose(coreDisplay) }

        guard let symbol = dlsym(coreDisplay, "CoreDisplay_Display_GetUserBrightness") else {
            return nil
        }

        let getBrightness = unsafeBitCast(symbol, to: GetBrightnessFunc.self)

        // Get main display ID
        let mainDisplay = CGMainDisplayID()
        guard CGDisplayIsBuiltin(mainDisplay) != 0 else {
            return nil
        }

        return getBrightness(mainDisplay)
    }

    /// Set brightness for built-in display using CoreDisplay private API
    func setBuiltInBrightness(_ brightness: Float) -> Bool {
        typealias SetBrightnessFunc = @convention(c) (UInt32, Double) -> Void

        guard let coreDisplay = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY) else {
            return false
        }
        defer { dlclose(coreDisplay) }

        guard let symbol = dlsym(coreDisplay, "CoreDisplay_Display_SetUserBrightness") else {
            return false
        }

        let setBrightness = unsafeBitCast(symbol, to: SetBrightnessFunc.self)

        let mainDisplay = CGMainDisplayID()
        guard CGDisplayIsBuiltin(mainDisplay) != 0 else {
            return false
        }

        let clampedBrightness = max(0.0, min(1.0, Double(brightness)))
        setBrightness(mainDisplay, clampedBrightness)

        return true
    }
}
