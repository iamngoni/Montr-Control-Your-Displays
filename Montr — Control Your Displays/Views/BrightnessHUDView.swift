import SwiftUI
import AppKit

/// macOS-style HUD overlay for brightness changes
struct BrightnessHUDView: View {
    let brightness: Int
    let displayName: String

    var body: some View {
        VStack(spacing: 12) {
            // Sun icon
            Image(systemName: brightness < 50 ? "sun.min.fill" : "sun.max.fill")
                .font(.system(size: 48))
                .foregroundColor(.white)

            // Brightness bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.3))

                    // Filled portion
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white)
                        .frame(width: geometry.size.width * CGFloat(brightness) / 100)
                }
            }
            .frame(height: 8)

            // Display name
            Text(displayName)
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(24)
        .frame(width: 200)
        .background(
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
        )
        .cornerRadius(16)
    }
}

// MARK: - Visual Effect Blur

struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - HUD Window Controller

@MainActor
final class BrightnessHUDController {
    static let shared = BrightnessHUDController()

    private var hudWindow: NSWindow?
    private var hideTimer: Timer?

    private init() {
        setupNotificationObserver()
    }

    private func setupNotificationObserver() {
        NotificationCenter.default.addObserver(
            forName: .brightnessDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let brightness = notification.userInfo?["brightness"] as? Int,
                  let displayId = notification.userInfo?["displayId"] as? String else {
                return
            }

            Task { @MainActor in
                self?.showHUD(brightness: brightness, displayId: displayId)
            }
        }
    }

    func showHUD(brightness: Int, displayId: String) {
        // Get display name
        let displayName = DisplayManager.shared.displays
            .first { $0.stableIdentifier == displayId }?
            .displayName ?? "Display"

        // Create or update window
        if hudWindow == nil {
            createHUDWindow()
        }

        // Update content
        let hudView = BrightnessHUDView(brightness: brightness, displayName: displayName)
        hudWindow?.contentView = NSHostingView(rootView: hudView)

        // Position window
        positionHUDWindow()

        // Show window
        hudWindow?.orderFrontRegardless()

        // Auto-hide after delay
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.hideHUD()
            }
        }
    }

    private func createHUDWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 140),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        hudWindow = window
    }

    private func positionHUDWindow() {
        guard let window = hudWindow,
              let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let windowSize = window.frame.size

        let x = screenFrame.midX - windowSize.width / 2
        let y = screenFrame.minY + 100 // Position near bottom of screen

        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func hideHUD() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            hudWindow?.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.hudWindow?.orderOut(nil)
            self?.hudWindow?.alphaValue = 1
        }
    }
}

// MARK: - Preview

#Preview {
    BrightnessHUDView(brightness: 75, displayName: "Built-in Display")
        .background(Color.black)
}
