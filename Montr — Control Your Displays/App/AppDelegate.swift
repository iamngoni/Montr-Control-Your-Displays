import AppKit
import SwiftUI
import Combine
import Sentry

/// App delegate handling lifecycle and menu bar
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - Properties

    private var menuBarController: MenuBarController?
    private var brightnessHUDController: BrightnessHUDController?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize Sentry for crash reporting (if enabled)
        initializeSentry()

        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)

        // Initialize services
        initializeServices()

        // Setup menu bar
        menuBarController = MenuBarController()

        // Setup HUD
        brightnessHUDController = BrightnessHUDController.shared

        // Capture original display settings for restoration
        BrightnessController.shared.captureOriginalSettings()

        // Check for location permission for sunrise/sunset
        if SettingsManager.shared.nightShiftSchedule.mode == .sunsetToSunrise {
            SunriseSunsetService.shared.requestLocationPermission()
        }

        // Show onboarding if needed
        if !SettingsManager.shared.hasCompletedOnboarding {
            // Could show onboarding window here
            SettingsManager.shared.hasCompletedOnboarding = true
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Restore original display settings if configured
        if SettingsManager.shared.restoreOnQuit {
            BrightnessController.shared.restoreOriginalSettings()
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    // MARK: - Private Methods

    private func initializeSentry() {
        // Only initialize Sentry if user has enabled crash reporting
        guard SettingsManager.shared.sentryEnabled else { return }

        SentrySDK.start { options in
            options.dsn = "https://4ad1279d5985f2378b2f4548aa7e4e35@o1107818.ingest.us.sentry.io/4510711782703104"
            options.debug = false

            // Set sample rate for performance monitoring
            options.tracesSampleRate = 0.1

            // Enable automatic breadcrumbs
            options.enableAutoBreadcrumbTracking = true

            // Set environment
            #if DEBUG
            options.environment = "development"
            #else
            options.environment = "production"
            #endif

            // Set release version
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
               let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                options.releaseName = "montr@\(version)+\(build)"
            }
        }
    }

    private func initializeServices() {
        // Touch singletons to initialize them
        _ = DisplayManager.shared
        _ = BrightnessController.shared
        _ = ColorTemperatureController.shared
        _ = ProfileManager.shared
        _ = HotkeyManager.shared
        _ = SunriseSunsetService.shared
        _ = MediaKeyManager.shared
    }
}
