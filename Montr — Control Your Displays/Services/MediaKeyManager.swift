import Cocoa
import Combine
import CoreGraphics
import Foundation

/// Manages interception of media keys (brightness/volume) for external display control
@MainActor
final class MediaKeyManager: ObservableObject {
    // MARK: - Published Properties

    @Published private(set) var isEnabled: Bool = false
    @Published private(set) var isRunning: Bool = false

    // MARK: - Private Properties

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // Media key codes (from IOKit/hidsystem/ev_keymap.h)
    private enum MediaKey: Int32 {
        case brightnessUp = 2
        case brightnessDown = 3
        case mute = 7
        case volumeDown = 9
        case volumeUp = 8
    }

    // MARK: - Singleton

    @MainActor static let shared = MediaKeyManager()

    private init() {
        isEnabled = SettingsManager.shared.mediaKeysEnabled
        if isEnabled {
            start()
        }
    }

    // MARK: - Public Methods

    /// Enable or disable media key interception
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        SettingsManager.shared.mediaKeysEnabled = enabled

        if enabled {
            start()
        } else {
            stop()
        }
    }

    /// Start intercepting media keys
    func start() {
        guard !isRunning else { return }

        // Create event tap for system-defined events (media keys)
        // NSEvent.EventType.systemDefined has raw value 14
        let eventMask: CGEventMask = 1 << 14

        // Use a static callback wrapper since we can't capture self directly
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passRetained(event) }
            let manager = Unmanaged<MediaKeyManager>.fromOpaque(refcon).takeUnretainedValue()
            return manager.handleEvent(proxy: proxy, type: type, event: event)
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: eventMask,
                callback: callback,
                userInfo: refcon
            )
        else {
            print("MediaKeyManager: Failed to create event tap. Check Accessibility permissions.")
            return
        }

        eventTap = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source

        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        isRunning = true
        print("MediaKeyManager: Started intercepting media keys")
    }

    /// Stop intercepting media keys
    func stop() {
        guard isRunning else { return }

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        isRunning = false

        print("MediaKeyManager: Stopped intercepting media keys")
    }

    // MARK: - Private Methods

    private func handleEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        // Re-enable tap if it was disabled due to timeout
        if type == .tapDisabledByTimeout {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        // Only handle system-defined events (raw value 14)
        guard type.rawValue == 14 else {
            return Unmanaged.passRetained(event)
        }

        // Parse the NSEvent to get media key info
        guard let nsEvent = NSEvent(cgEvent: event) else {
            return Unmanaged.passRetained(event)
        }

        // Check if this is a media key event (subtype 8)
        guard nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passRetained(event)
        }

        // Parse the key data
        // data1 layout: bits 16-23 = key code, bits 8-11 = flags (bit 8 = key down)
        let data = nsEvent.data1
        let keyCode = Int32((data & 0xFFFF_0000) >> 16)
        let keyDown = ((data & 0x0000_FF00) >> 8) == 0x0A  // 0x0A = key down

        // Only handle key down events
        guard keyDown else {
            return Unmanaged.passRetained(event)
        }

        // Check if we should handle this key
        guard let mediaKey = MediaKey(rawValue: keyCode) else {
            return Unmanaged.passRetained(event)
        }

        // Handle the media key
        let handled = handleMediaKey(mediaKey)

        // If we handled it, don't pass the event to other handlers
        if handled {
            return nil
        }

        return Unmanaged.passRetained(event)
    }

    private func handleMediaKey(_ key: MediaKey) -> Bool {
        // Only intercept if we have external displays
        let displays = DisplayManager.shared.displays
        let hasExternalDisplays = displays.contains { !$0.isBuiltIn && !$0.isSidecar }

        guard hasExternalDisplays else {
            return false  // Let system handle it
        }

        Task { @MainActor in
            switch key {
            case .brightnessUp:
                await BrightnessController.shared.adjustBrightnessForAll(by: 5)

            case .brightnessDown:
                await BrightnessController.shared.adjustBrightnessForAll(by: -5)

            case .volumeUp:
                await BrightnessController.shared.adjustVolumeForAll(by: 5)

            case .volumeDown:
                await BrightnessController.shared.adjustVolumeForAll(by: -5)

            case .mute:
                // Toggle mute for all volume-supporting displays
                let displays = DisplayManager.shared.displays
                for display in displays where BrightnessController.shared.supportsVolume(for: display)
                {
                    await BrightnessController.shared.toggleMute(for: display)
                }
            }
        }

        return true  // We handled it
    }
}
