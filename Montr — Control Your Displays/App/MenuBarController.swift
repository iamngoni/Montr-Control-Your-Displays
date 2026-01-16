import AppKit
import Combine
import SwiftUI

/// Controls the menu bar status item and popover
@MainActor
final class MenuBarController: NSObject, ObservableObject {
    // MARK: - Properties

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var eventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    override init() {
        super.init()
        setupStatusItem()
        setupPopover()
        setupEventMonitor()
        setupNotificationObservers()
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem?.button else { return }

        // Set icon
        updateIcon()

        // Set click action
        button.action = #selector(togglePopover)
        button.target = self

        // Set right-click menu
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func setupPopover() {
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 360, height: 420)
        popover?.behavior = .transient
        popover?.animates = true
        popover?.contentViewController = NSHostingController(rootView: PopoverContentView())
    }

    private func setupEventMonitor() {
        // Close popover when clicking outside
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [
            .leftMouseDown, .rightMouseDown,
        ]) { [weak self] event in
            if let popover = self?.popover, popover.isShown {
                self?.closePopover()
            }
        }
    }

    private func setupNotificationObservers() {
        // Listen for hotkey to open popover
        NotificationCenter.default.publisher(for: .openMontrPopover)
            .sink { [weak self] _ in
                self?.showPopover()
            }
            .store(in: &cancellables)

        // Listen for settings opening request - close popover first
        NotificationCenter.default.publisher(for: .openMontrSettings)
            .sink { [weak self] _ in
                self?.closePopover()
                self?.openSettingsWindow()
            }
            .store(in: &cancellables)
    }

    private func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)

        // Check if settings window is already open
        if let settingsWindow = NSApp.windows.first(where: {
            $0.identifier?.rawValue.contains("Settings") == true || $0.title.contains("Settings")
                || $0.title.contains("Preferences")
        }) {
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }

        // Open settings window
        // Note: The console warning about SettingsLink is informational
        // and doesn't prevent the settings window from opening
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    // MARK: - Actions

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent

        if event?.type == .rightMouseUp {
            showContextMenu()
        } else if event?.modifierFlags.contains(.option) == true {
            // Option-click to quit
            NSApp.terminate(nil)
        } else {
            if popover?.isShown == true {
                closePopover()
            } else {
                showPopover()
            }
        }
    }

    func showPopover() {
        guard let button = statusItem?.button,
            let popover = popover
        else { return }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        // Activate app to bring popover to front
        NSApp.activate(ignoringOtherApps: true)
    }

    func closePopover() {
        popover?.performClose(nil)
    }

    private func showContextMenu() {
        let menu = NSMenu()

        // Profiles submenu
        let profilesItem = NSMenuItem(title: "Profiles", action: nil, keyEquivalent: "")
        let profilesMenu = NSMenu()

        Task { @MainActor in
            let profileManager = ProfileManager.shared
            for profile in profileManager.profiles {
                let item = NSMenuItem(
                    title: profile.name, action: #selector(selectProfile(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = profile.id
                if profileManager.activeProfile?.id == profile.id {
                    item.state = .on
                }
                profilesMenu.addItem(item)
            }
        }

        profilesItem.submenu = profilesMenu
        menu.addItem(profilesItem)

        menu.addItem(NSMenuItem.separator())

        // Quick Dim
        let quickDimItem = NSMenuItem(
            title: "Quick Dim", action: #selector(toggleQuickDim), keyEquivalent: "d")
        quickDimItem.target = self
        quickDimItem.keyEquivalentModifierMask = [.option, .command]
        if BrightnessController.shared.quickDimEnabled {
            quickDimItem.state = .on
        }
        menu.addItem(quickDimItem)

        // Night Shift
        let nightShiftItem = NSMenuItem(
            title: "Night Shift", action: #selector(toggleNightShift), keyEquivalent: "n")
        nightShiftItem.target = self
        nightShiftItem.keyEquivalentModifierMask = [.option, .command]
        if ColorTemperatureController.shared.isEnabled {
            nightShiftItem.state = .on
        }
        menu.addItem(nightShiftItem)

        menu.addItem(NSMenuItem.separator())

        // Settings
        let settingsItem = NSMenuItem(
            title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit Montr", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func selectProfile(_ sender: NSMenuItem) {
        guard let profileId = sender.representedObject as? UUID else { return }

        Task { @MainActor in
            let profileManager = ProfileManager.shared
            if let profile = profileManager.profiles.first(where: { $0.id == profileId }) {
                await profileManager.applyProfile(profile)
            }
        }
    }

    @objc private func toggleQuickDim() {
        Task { @MainActor in
            await BrightnessController.shared.toggleQuickDim()
        }
    }

    @objc private func toggleNightShift() {
        Task { @MainActor in
            await ColorTemperatureController.shared.toggle()
        }
    }

    @objc private func openSettings() {
        closePopover()
        openSettingsWindow()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Icon Updates

    private func updateIcon() {
        guard let button = statusItem?.button else { return }

        // Always use a white monitor icon
        if let image = NSImage(systemSymbolName: "display", accessibilityDescription: "Montr") {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            if let configuredImage = image.withSymbolConfiguration(config) {
                let finalImage = configuredImage.copy() as! NSImage
                finalImage.isTemplate = true  // Template for proper menu bar appearance (white)
                button.image = finalImage
                button.contentTintColor = nil
            }
        }
    }
}
