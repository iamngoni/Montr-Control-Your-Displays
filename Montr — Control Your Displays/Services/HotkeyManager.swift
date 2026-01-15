import Foundation
import Carbon
import AppKit
import Combine

/// Manages global keyboard shortcuts
@MainActor
final class HotkeyManager: ObservableObject, @unchecked Sendable {
    // MARK: - Published Properties

    @Published private(set) var registeredHotkeys: [HotkeyAction: Hotkey] = [:]
    @Published private(set) var isEnabled: Bool = true

    // MARK: - Hotkey Actions

    enum HotkeyAction: String, CaseIterable, Codable {
        case openMontr = "Open Montr"
        case toggleQuickDim = "Toggle Quick Dim"
        case brightnessUp = "Brightness Up"
        case brightnessDown = "Brightness Down"
        case toggleNightShift = "Toggle Night Shift"
        case nextProfile = "Next Profile"

        var defaultHotkey: Hotkey {
            switch self {
            case .openMontr:
                return Hotkey(keyCode: kVK_ANSI_M, modifiers: [.option, .command])
            case .toggleQuickDim:
                return Hotkey(keyCode: kVK_ANSI_D, modifiers: [.option, .command])
            case .brightnessUp:
                return Hotkey(keyCode: kVK_UpArrow, modifiers: [.option, .command])
            case .brightnessDown:
                return Hotkey(keyCode: kVK_DownArrow, modifiers: [.option, .command])
            case .toggleNightShift:
                return Hotkey(keyCode: kVK_ANSI_N, modifiers: [.option, .command])
            case .nextProfile:
                return Hotkey(keyCode: kVK_ANSI_P, modifiers: [.option, .command])
            }
        }
    }

    // MARK: - Hotkey Structure

    struct Hotkey: Codable, Equatable {
        let keyCode: Int
        let modifiers: Set<ModifierKey>

        enum ModifierKey: String, Codable {
            case command
            case option
            case control
            case shift

            var carbonFlag: Int {
                switch self {
                case .command: return cmdKey
                case .option: return optionKey
                case .control: return controlKey
                case .shift: return shiftKey
                }
            }

            var symbol: String {
                switch self {
                case .command: return "⌘"
                case .option: return "⌥"
                case .control: return "⌃"
                case .shift: return "⇧"
                }
            }
        }

        var carbonModifiers: UInt32 {
            var result: UInt32 = 0
            for modifier in modifiers {
                result |= UInt32(modifier.carbonFlag)
            }
            return result
        }

        var displayString: String {
            var parts: [String] = []
            if modifiers.contains(.control) { parts.append("⌃") }
            if modifiers.contains(.option) { parts.append("⌥") }
            if modifiers.contains(.shift) { parts.append("⇧") }
            if modifiers.contains(.command) { parts.append("⌘") }
            parts.append(keyCodeToString(keyCode))
            return parts.joined()
        }

        private func keyCodeToString(_ keyCode: Int) -> String {
            switch keyCode {
            case kVK_ANSI_A: return "A"
            case kVK_ANSI_B: return "B"
            case kVK_ANSI_C: return "C"
            case kVK_ANSI_D: return "D"
            case kVK_ANSI_E: return "E"
            case kVK_ANSI_F: return "F"
            case kVK_ANSI_G: return "G"
            case kVK_ANSI_H: return "H"
            case kVK_ANSI_I: return "I"
            case kVK_ANSI_J: return "J"
            case kVK_ANSI_K: return "K"
            case kVK_ANSI_L: return "L"
            case kVK_ANSI_M: return "M"
            case kVK_ANSI_N: return "N"
            case kVK_ANSI_O: return "O"
            case kVK_ANSI_P: return "P"
            case kVK_ANSI_Q: return "Q"
            case kVK_ANSI_R: return "R"
            case kVK_ANSI_S: return "S"
            case kVK_ANSI_T: return "T"
            case kVK_ANSI_U: return "U"
            case kVK_ANSI_V: return "V"
            case kVK_ANSI_W: return "W"
            case kVK_ANSI_X: return "X"
            case kVK_ANSI_Y: return "Y"
            case kVK_ANSI_Z: return "Z"
            case kVK_UpArrow: return "↑"
            case kVK_DownArrow: return "↓"
            case kVK_LeftArrow: return "←"
            case kVK_RightArrow: return "→"
            case kVK_Space: return "Space"
            case kVK_Return: return "↩"
            case kVK_Tab: return "⇥"
            case kVK_Escape: return "⎋"
            default: return "?"
            }
        }
    }

    // MARK: - Private Properties

    private var hotkeyRefs: [HotkeyAction: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?

    // MARK: - Singleton

    @MainActor static let shared = HotkeyManager()

    private init() {
        loadSavedHotkeys()
        setupEventHandler()
        registerAllHotkeys()
    }

    // Note: No deinit needed for singleton - it lives for the app's lifetime

    // MARK: - Public Methods

    /// Set a hotkey for an action
    func setHotkey(_ hotkey: Hotkey, for action: HotkeyAction) {
        // Unregister existing hotkey for this action
        unregisterHotkey(for: action)

        // Register new hotkey
        registeredHotkeys[action] = hotkey
        registerHotkey(hotkey, for: action)

        saveHotkeys()
    }

    /// Remove a hotkey for an action
    func removeHotkey(for action: HotkeyAction) {
        unregisterHotkey(for: action)
        registeredHotkeys.removeValue(forKey: action)
        saveHotkeys()
    }

    /// Reset all hotkeys to defaults
    func resetToDefaults() {
        unregisterAllHotkeys()
        registeredHotkeys.removeAll()

        for action in HotkeyAction.allCases {
            registeredHotkeys[action] = action.defaultHotkey
        }

        registerAllHotkeys()
        saveHotkeys()
    }

    /// Enable or disable hotkeys
    func setEnabled(_ enabled: Bool) {
        if enabled && !isEnabled {
            registerAllHotkeys()
        } else if !enabled && isEnabled {
            unregisterAllHotkeys()
        }
        isEnabled = enabled
    }

    // MARK: - Private Methods

    private func loadSavedHotkeys() {
        if let savedHotkeys = SettingsManager.shared.hotkeys {
            registeredHotkeys = savedHotkeys
        } else {
            // Use defaults
            for action in HotkeyAction.allCases {
                registeredHotkeys[action] = action.defaultHotkey
            }
        }
    }

    private func saveHotkeys() {
        SettingsManager.shared.hotkeys = registeredHotkeys
    }

    private func setupEventHandler() {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerCallback: EventHandlerUPP = { _, event, userData -> OSStatus in
            guard let event = event,
                  let userData = userData else {
                return OSStatus(eventNotHandledErr)
            }

            var hotkeyId = EventHotKeyID()
            let error = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotkeyId
            )

            guard error == noErr else {
                return OSStatus(eventNotHandledErr)
            }

            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            Task { @MainActor in
                manager.handleHotkey(id: hotkeyId.id)
            }

            return noErr
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            handlerCallback,
            1,
            &eventSpec,
            selfPtr,
            &eventHandler
        )
    }

    private func registerAllHotkeys() {
        for (action, hotkey) in registeredHotkeys {
            registerHotkey(hotkey, for: action)
        }
    }

    private func unregisterAllHotkeys() {
        for (action, _) in hotkeyRefs {
            unregisterHotkey(for: action)
        }
    }

    private func registerHotkey(_ hotkey: Hotkey, for action: HotkeyAction) {
        // Use index in allCases as the unique ID (safe UInt32)
        let actionIndex = HotkeyAction.allCases.firstIndex(of: action) ?? 0
        let hotkeyId = EventHotKeyID(signature: OSType(0x4D4F4E54), id: UInt32(actionIndex)) // "MONT"
        var hotkeyRef: EventHotKeyRef?

        let status = RegisterEventHotKey(
            UInt32(hotkey.keyCode),
            hotkey.carbonModifiers,
            hotkeyId,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        if status == noErr, let ref = hotkeyRef {
            hotkeyRefs[action] = ref
        }
    }

    private func unregisterHotkey(for action: HotkeyAction) {
        if let ref = hotkeyRefs[action] {
            UnregisterEventHotKey(ref)
            hotkeyRefs.removeValue(forKey: action)
        }
    }

    private func handleHotkey(id: UInt32) {
        // Find the action for this hotkey ID (ID is index in allCases)
        let allCases = HotkeyAction.allCases
        let index = Int(id)
        if index >= 0 && index < allCases.count {
            executeAction(allCases[index])
        }
    }

    private func executeAction(_ action: HotkeyAction) {
        Task { @MainActor in
            switch action {
            case .openMontr:
                NotificationCenter.default.post(name: .openMontrPopover, object: nil)

            case .toggleQuickDim:
                await BrightnessController.shared.toggleQuickDim()

            case .brightnessUp:
                await BrightnessController.shared.adjustBrightnessForAll(by: 5)

            case .brightnessDown:
                await BrightnessController.shared.adjustBrightnessForAll(by: -5)

            case .toggleNightShift:
                await ColorTemperatureController.shared.toggle()

            case .nextProfile:
                await cycleToNextProfile()
            }
        }
    }

    private func cycleToNextProfile() async {
        let profileManager = ProfileManager.shared
        let profiles = profileManager.profiles

        guard !profiles.isEmpty else { return }

        if let currentProfile = profileManager.activeProfile,
           let currentIndex = profiles.firstIndex(where: { $0.id == currentProfile.id }) {
            let nextIndex = (currentIndex + 1) % profiles.count
            await profileManager.applyProfile(profiles[nextIndex])
        } else {
            await profileManager.applyProfile(profiles[0])
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let openMontrPopover = Notification.Name("openMontrPopover")
    static let openMontrSettings = Notification.Name("openMontrSettings")
}
