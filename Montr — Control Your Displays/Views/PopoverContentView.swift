import SwiftUI

// MARK: - Design System

private enum MontrTheme {
    // Colors
    static let background = Color(red: 0.11, green: 0.12, blue: 0.14)
    static let cardBackground = Color(red: 0.15, green: 0.16, blue: 0.18)
    static let teal = Color(red: 0.0, green: 0.78, blue: 0.73)
    static let tealDark = Color(red: 0.0, green: 0.55, blue: 0.52)
    static let warmOrange = Color(red: 1.0, green: 0.6, blue: 0.2)
    static let connectedGreen = Color(red: 0.2, green: 0.8, blue: 0.4)
    static let textPrimary = Color.white
    static let textSecondary = Color(white: 0.55)
    static let sliderTrack = Color(white: 0.25)
}

// MARK: - Main View

struct PopoverContentView: View {
    @StateObject private var displayManager = DisplayManager.shared
    @StateObject private var brightnessController = BrightnessController.shared
    @StateObject private var colorTempController = ColorTemperatureController.shared
    @StateObject private var profileManager = ProfileManager.shared
    @State private var selectedDisplayIndex: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            // Content
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    // Displays section with tabs
                    if displayManager.displays.isEmpty {
                        EmptyDisplayState()
                    } else {
                        VStack(spacing: 0) {
                            // Tab bar (index 0 = All, 1+ = individual displays)
                            DisplayTabBar(
                                displays: displayManager.displays,
                                selectedIndex: $selectedDisplayIndex,
                                showAllTab: displayManager.displays.count > 1
                            )

                            // Selected display content
                            if selectedDisplayIndex == 0 && displayManager.displays.count > 1 {
                                // "All" tab selected - show universal controls
                                AllDisplaysContent(displays: displayManager.displays)
                            } else {
                                // Individual display selected
                                let displayIndex = displayManager.displays.count > 1 ? selectedDisplayIndex - 1 : selectedDisplayIndex
                                if displayIndex >= 0 && displayIndex < displayManager.displays.count {
                                    DisplayTabContent(display: displayManager.displays[displayIndex])
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(MontrTheme.cardBackground)
                        )
                    }

                    // Night Shift
                    NightShiftSection()

                    // Profiles
                    ProfilesSection()
                }
                .padding(.horizontal, 16)
            }

            Spacer(minLength: 12)

            // Footer
            footerView
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .frame(width: 320, height: 420)
        .background(MontrTheme.background)
        .onChange(of: displayManager.displays.count) { _, newCount in
            // Reset selection if needed when displays change
            // Index 0 = "All" (only shown if > 1 display), index 1+ = individual displays
            let maxIndex = newCount > 1 ? newCount : max(0, newCount - 1)
            if selectedDisplayIndex > maxIndex {
                selectedDisplayIndex = 0
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 12) {
            // App icon and name
            HStack(spacing: 8) {
                // Teal app icon
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(MontrTheme.teal)
                        .frame(width: 24, height: 24)

                    Image(systemName: "display")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                }

                Text("Montr")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(MontrTheme.textPrimary)
            }

            Spacer()

            // Quick Dim button
            QuickDimButton()

            // Settings button
            SettingsLink {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14))
                    .foregroundColor(MontrTheme.textSecondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Text(appVersion)
                .font(.system(size: 11))
                .foregroundColor(MontrTheme.textSecondary)

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(
                        displayManager.displays.isEmpty
                            ? MontrTheme.textSecondary : MontrTheme.connectedGreen
                    )
                    .frame(width: 6, height: 6)

                Text(displayManager.displays.isEmpty ? "No Displays" : "Connected")
                    .font(.system(size: 11))
                    .foregroundColor(MontrTheme.textSecondary)
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "v\(version)"
    }
}

// MARK: - Quick Dim Button

private struct QuickDimButton: View {
    @StateObject private var brightnessController = BrightnessController.shared
    @State private var isHovering = false

    var body: some View {
        Button {
            Task { await brightnessController.toggleQuickDim() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .medium))

                Text("Quick Dim")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(
                brightnessController.quickDimEnabled ? .black : MontrTheme.textSecondary
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(brightnessController.quickDimEnabled ? MontrTheme.teal : Color.clear)
                    .overlay(
                        Capsule()
                            .stroke(
                                brightnessController.quickDimEnabled
                                    ? Color.clear : MontrTheme.textSecondary.opacity(0.3),
                                lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Display Tab Bar

private struct DisplayTabBar: View {
    let displays: [Display]
    @Binding var selectedIndex: Int
    var showAllTab: Bool = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                // "All" tab (only shown if multiple displays)
                if showAllTab {
                    AllDisplaysTab(isSelected: selectedIndex == 0) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedIndex = 0
                        }
                    }

                    Rectangle()
                        .fill(MontrTheme.sliderTrack)
                        .frame(width: 1, height: 20)
                }

                // Individual display tabs
                ForEach(Array(displays.enumerated()), id: \.element.id) { index, display in
                    let tabIndex = showAllTab ? index + 1 : index

                    DisplayTab(
                        display: display,
                        isSelected: tabIndex == selectedIndex
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedIndex = tabIndex
                        }
                    }

                    // Separator between tabs (not after last)
                    if index < displays.count - 1 {
                        Rectangle()
                            .fill(MontrTheme.sliderTrack)
                            .frame(width: 1, height: 20)
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
        .background(
            VStack(spacing: 0) {
                Spacer()
                Rectangle()
                    .fill(MontrTheme.sliderTrack)
                    .frame(height: 1)
            }
        )
    }
}

// MARK: - All Displays Tab

private struct AllDisplaysTab: View {
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.on.rectangle")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isSelected ? MontrTheme.teal : MontrTheme.textSecondary)

                Text("All")
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? MontrTheme.teal : MontrTheme.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? MontrTheme.teal.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - All Displays Content

private struct AllDisplaysContent: View {
    let displays: [Display]

    @StateObject private var brightnessController = BrightnessController.shared
    @State private var brightness: Double = 100
    @State private var volume: Double = 50
    @State private var isMuted: Bool = false

    // Check if any display supports volume
    private var anySupportsVolume: Bool {
        displays.contains { brightnessController.supportsVolume(for: $0) }
    }

    // Calculate average brightness across all displays
    private var averageBrightness: Double {
        guard !displays.isEmpty else { return 100 }
        let total = displays.reduce(0) { $0 + brightnessController.getBrightness(for: $1) }
        return Double(total) / Double(displays.count)
    }

    // Calculate average volume across volume-supporting displays
    private var averageVolume: Double {
        let volumeDisplays = displays.filter { brightnessController.supportsVolume(for: $0) }
        guard !volumeDisplays.isEmpty else { return 50 }
        let total = volumeDisplays.reduce(0) { $0 + brightnessController.getVolume(for: $1) }
        return Double(total) / Double(volumeDisplays.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("All Displays")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(MontrTheme.textPrimary)

                    Text("\(displays.count) connected")
                        .font(.system(size: 11))
                        .foregroundColor(MontrTheme.textSecondary)
                }

                Spacer()

                // Sync indicator
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.system(size: 9))
                    Text("SYNC")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundColor(MontrTheme.teal)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(MontrTheme.teal.opacity(0.15))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(MontrTheme.teal.opacity(0.5), lineWidth: 1)
                )
            }

            // Brightness control
            VStack(alignment: .leading, spacing: 8) {
                Text("BRIGHTNESS")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(MontrTheme.textSecondary)
                    .tracking(0.5)

                HStack(spacing: 12) {
                    Image(systemName: "sun.min.fill")
                        .font(.system(size: 12))
                        .foregroundColor(MontrTheme.textSecondary)

                    // Custom slider
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Track background
                            Capsule()
                                .fill(MontrTheme.sliderTrack)
                                .frame(height: 6)

                            // Filled track
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [MontrTheme.tealDark, MontrTheme.teal],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(
                                    width: max(6, geometry.size.width * (brightness / 100)), height: 6)

                            // Thumb
                            Circle()
                                .fill(.white)
                                .frame(width: 14, height: 14)
                                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                                .offset(
                                    x: max(
                                        0,
                                        min(
                                            geometry.size.width - 14,
                                            (geometry.size.width - 14) * (brightness / 100))))
                        }
                        .frame(height: 20)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { gesture in
                                    let newValue = min(
                                        max(0, gesture.location.x / geometry.size.width * 100), 100)
                                    brightness = newValue
                                }
                                .onEnded { _ in
                                    // Apply brightness to all displays
                                    Task {
                                        for display in displays {
                                            await brightnessController.setBrightness(
                                                for: display, value: Int(brightness))
                                        }
                                    }
                                }
                        )
                    }
                    .frame(height: 20)

                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 12))
                        .foregroundColor(MontrTheme.textSecondary)

                    Text("\(Int(brightness))%")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(MontrTheme.textPrimary)
                        .frame(width: 40, alignment: .trailing)
                        .monospacedDigit()
                }
            }

            // Volume control (only if any display supports it)
            if anySupportsVolume {
                VStack(alignment: .leading, spacing: 8) {
                    Text("VOLUME")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(MontrTheme.textSecondary)
                        .tracking(0.5)

                    HStack(spacing: 12) {
                        // Mute button
                        Button {
                            Task {
                                for display in displays where brightnessController.supportsVolume(for: display) {
                                    await brightnessController.setMuted(for: display, muted: !isMuted)
                                }
                                isMuted.toggle()
                            }
                        } label: {
                            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.1.fill")
                                .font(.system(size: 12))
                                .foregroundColor(isMuted ? MontrTheme.warmOrange : MontrTheme.textSecondary)
                        }
                        .buttonStyle(.plain)

                        // Volume slider
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                // Track background
                                Capsule()
                                    .fill(MontrTheme.sliderTrack)
                                    .frame(height: 6)

                                // Filled track
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [MontrTheme.tealDark, MontrTheme.teal],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(
                                        width: max(6, geometry.size.width * (volume / 100)), height: 6)
                                    .opacity(isMuted ? 0.4 : 1.0)

                                // Thumb
                                Circle()
                                    .fill(.white)
                                    .frame(width: 14, height: 14)
                                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                                    .offset(
                                        x: max(
                                            0,
                                            min(
                                                geometry.size.width - 14,
                                                (geometry.size.width - 14) * (volume / 100))))
                                    .opacity(isMuted ? 0.6 : 1.0)
                            }
                            .frame(height: 20)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { gesture in
                                        let newValue = min(
                                            max(0, gesture.location.x / geometry.size.width * 100), 100)
                                        volume = newValue
                                        // Unmute when adjusting volume
                                        if isMuted {
                                            isMuted = false
                                            Task {
                                                for display in displays where brightnessController.supportsVolume(for: display) {
                                                    await brightnessController.setMuted(for: display, muted: false)
                                                }
                                            }
                                        }
                                    }
                                    .onEnded { _ in
                                        // Apply volume to all displays that support it
                                        Task {
                                            for display in displays where brightnessController.supportsVolume(for: display) {
                                                await brightnessController.setVolume(
                                                    for: display, value: Int(volume))
                                            }
                                        }
                                    }
                            )
                        }
                        .frame(height: 20)

                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(size: 12))
                            .foregroundColor(MontrTheme.textSecondary)

                        Text("\(Int(volume))%")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(isMuted ? MontrTheme.textSecondary : MontrTheme.textPrimary)
                            .frame(width: 40, alignment: .trailing)
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding(16)
        .onAppear {
            brightness = averageBrightness
            volume = averageVolume
        }
    }
}

// MARK: - Display Tab

private struct DisplayTab: View {
    let display: Display
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                // Connection indicator
                Circle()
                    .fill(MontrTheme.connectedGreen)
                    .frame(width: 6, height: 6)

                // Display name (truncated if needed)
                Text(display.shortDisplayName)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? MontrTheme.teal : MontrTheme.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? MontrTheme.teal.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Display Tab Content

private struct DisplayTabContent: View {
    let display: Display

    @StateObject private var brightnessController = BrightnessController.shared
    @State private var brightness: Double = 100
    @State private var volume: Double = 50
    @State private var isMuted: Bool = false

    private var supportsVolume: Bool {
        brightnessController.supportsVolume(for: display)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Display info header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(display.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(MontrTheme.textPrimary)

                    Text(display.connectionType.displayName)
                        .font(.system(size: 11))
                        .foregroundColor(MontrTheme.textSecondary)
                }

                Spacer()

                // Control method badge
                Text(display.controlMethodBadge)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(MontrTheme.teal)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(MontrTheme.teal.opacity(0.15))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(MontrTheme.teal.opacity(0.5), lineWidth: 1)
                    )
            }

            // Brightness control
            VStack(alignment: .leading, spacing: 8) {
                Text("BRIGHTNESS")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(MontrTheme.textSecondary)
                    .tracking(0.5)

                HStack(spacing: 12) {
                    Image(systemName: "sun.min.fill")
                        .font(.system(size: 12))
                        .foregroundColor(MontrTheme.textSecondary)

                    // Custom slider
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Track background
                            Capsule()
                                .fill(MontrTheme.sliderTrack)
                                .frame(height: 6)

                            // Filled track
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [MontrTheme.tealDark, MontrTheme.teal],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(
                                    width: max(6, geometry.size.width * (brightness / 100)), height: 6)

                            // Thumb
                            Circle()
                                .fill(.white)
                                .frame(width: 14, height: 14)
                                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                                .offset(
                                    x: max(
                                        0,
                                        min(
                                            geometry.size.width - 14,
                                            (geometry.size.width - 14) * (brightness / 100))))
                        }
                        .frame(height: 20)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { gesture in
                                    let newValue = min(
                                        max(0, gesture.location.x / geometry.size.width * 100), 100)
                                    brightness = newValue
                                }
                                .onEnded { _ in
                                    Task {
                                        await brightnessController.setBrightness(
                                            for: display, value: Int(brightness))
                                    }
                                }
                        )
                    }
                    .frame(height: 20)

                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 12))
                        .foregroundColor(MontrTheme.textSecondary)

                    Text("\(Int(brightness))%")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(MontrTheme.textPrimary)
                        .frame(width: 40, alignment: .trailing)
                        .monospacedDigit()
                }
            }

            // Volume control (only for displays that support it)
            if supportsVolume {
                VStack(alignment: .leading, spacing: 8) {
                    Text("VOLUME")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(MontrTheme.textSecondary)
                        .tracking(0.5)

                    HStack(spacing: 12) {
                        // Mute button
                        Button {
                            Task {
                                await brightnessController.toggleMute(for: display)
                            }
                        } label: {
                            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.1.fill")
                                .font(.system(size: 12))
                                .foregroundColor(isMuted ? MontrTheme.warmOrange : MontrTheme.textSecondary)
                        }
                        .buttonStyle(.plain)

                        // Volume slider
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                // Track background
                                Capsule()
                                    .fill(MontrTheme.sliderTrack)
                                    .frame(height: 6)

                                // Filled track
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [MontrTheme.tealDark, MontrTheme.teal],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(
                                        width: max(6, geometry.size.width * (volume / 100)), height: 6)
                                    .opacity(isMuted ? 0.4 : 1.0)

                                // Thumb
                                Circle()
                                    .fill(.white)
                                    .frame(width: 14, height: 14)
                                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                                    .offset(
                                        x: max(
                                            0,
                                            min(
                                                geometry.size.width - 14,
                                                (geometry.size.width - 14) * (volume / 100))))
                                    .opacity(isMuted ? 0.6 : 1.0)
                            }
                            .frame(height: 20)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { gesture in
                                        let newValue = min(
                                            max(0, gesture.location.x / geometry.size.width * 100), 100)
                                        volume = newValue
                                        // Unmute when adjusting volume
                                        if isMuted {
                                            Task {
                                                await brightnessController.setMuted(for: display, muted: false)
                                            }
                                        }
                                    }
                                    .onEnded { _ in
                                        Task {
                                            await brightnessController.setVolume(
                                                for: display, value: Int(volume))
                                        }
                                    }
                            )
                        }
                        .frame(height: 20)

                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(size: 12))
                            .foregroundColor(MontrTheme.textSecondary)

                        Text("\(Int(volume))%")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(isMuted ? MontrTheme.textSecondary : MontrTheme.textPrimary)
                            .frame(width: 40, alignment: .trailing)
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding(16)
        .onAppear {
            brightness = Double(brightnessController.getBrightness(for: display))
            if supportsVolume {
                volume = Double(brightnessController.getVolume(for: display))
                isMuted = brightnessController.isMuted(for: display)
            }
        }
        .onChange(of: brightnessController.displayBrightness[display.stableIdentifier]) {
            _, newValue in
            if let newValue {
                brightness = Double(newValue)
            }
        }
        .onChange(of: brightnessController.displayVolume[display.stableIdentifier]) {
            _, newValue in
            if let newValue {
                volume = Double(newValue)
            }
        }
        .onChange(of: brightnessController.displayMuted[display.stableIdentifier]) {
            _, newValue in
            if let newValue {
                isMuted = newValue
            }
        }
    }
}

// MARK: - Night Shift Section

private struct NightShiftSection: View {
    @StateObject private var colorTempController = ColorTemperatureController.shared
    @State private var temperature: Double = 5625

    // Temperature range: 2700K (warmest/candlelight) to 6500K (coolest/daylight)
    private let minTemp: Double = 2700
    private let maxTemp: Double = 6500

    // Normalized value: 0 = warm (left), 1 = cool (right)
    // But we want warmer on left, candlelight on right, so we invert
    // Left (0) = 6500K (less warm), Right (1) = 2700K (warmest/candlelight)
    private var normalizedValue: Double {
        1.0 - (temperature - minTemp) / (maxTemp - minTemp)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 13))
                        .foregroundColor(MontrTheme.textSecondary)

                    Text("Night Shift")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(MontrTheme.textPrimary)
                }

                Spacer()

                // Toggle
                Toggle(
                    "",
                    isOn: Binding(
                        get: { colorTempController.isEnabled },
                        set: { newValue in
                            Task {
                                if newValue {
                                    await colorTempController.enable()
                                } else {
                                    await colorTempController.disable()
                                }
                            }
                        }
                    )
                )
                .toggleStyle(TealToggleStyle())
                .labelsHidden()
            }

            // Temperature slider - gradient from warm teal to warm orange (candlelight)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Gradient track: teal-ish on left (less warm) to orange on right (warmest)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [MontrTheme.teal, MontrTheme.warmOrange],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 8)
                        .opacity(colorTempController.isEnabled ? 1.0 : 0.4)

                    // Thumb
                    Circle()
                        .fill(.white)
                        .frame(width: 18, height: 18)
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                        )
                        .offset(
                            x: max(
                                0,
                                min(
                                    geometry.size.width - 18,
                                    (geometry.size.width - 18) * normalizedValue)))
                }
                .frame(height: 24)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            guard colorTempController.isEnabled else { return }
                            let normalized = min(
                                max(0, gesture.location.x / geometry.size.width), 1)
                            // Invert: right = warmer (lower K), left = cooler (higher K)
                            temperature = maxTemp - normalized * (maxTemp - minTemp)
                        }
                        .onEnded { _ in
                            Task {
                                await colorTempController.setGlobalTemperature(Int(temperature))
                            }
                        }
                )
            }
            .frame(height: 24)

            // Temperature labels (matching reference: Warm -> Warmer -> Candlelight)
            HStack {
                Text("Warm")
                    .font(.system(size: 10))
                    .foregroundColor(MontrTheme.textSecondary)

                Spacer()

                Text("Warmer")
                    .font(.system(size: 10))
                    .foregroundColor(MontrTheme.textSecondary)

                Spacer()

                Text("Candlelight")
                    .font(.system(size: 10))
                    .foregroundColor(MontrTheme.textSecondary)
            }

            // Mode and Kelvin
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 10))
                    Text("Manual")
                        .font(.system(size: 11))
                }
                .foregroundColor(MontrTheme.textSecondary)

                Spacer()

                Text("\(Int(temperature))K")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(MontrTheme.textPrimary)
                    .monospacedDigit()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(MontrTheme.cardBackground)
        )
        .onAppear {
            temperature = Double(colorTempController.globalTemperature)
        }
        .onChange(of: colorTempController.globalTemperature) { _, newValue in
            temperature = Double(newValue)
        }
    }
}

// MARK: - Teal Toggle Style

private struct TealToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label

            ZStack {
                Capsule()
                    .fill(configuration.isOn ? MontrTheme.teal : MontrTheme.sliderTrack)
                    .frame(width: 44, height: 24)

                Circle()
                    .fill(.white)
                    .frame(width: 20, height: 20)
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                    .offset(x: configuration.isOn ? 10 : -10)
            }
            .onTapGesture {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    configuration.isOn.toggle()
                }
            }
        }
    }
}

// MARK: - Profiles Section

private struct ProfilesSection: View {
    @StateObject private var profileManager = ProfileManager.shared
    @State private var showingNewProfile = false
    @State private var newProfileName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PROFILES")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(MontrTheme.textSecondary)
                .tracking(0.5)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(profileManager.profiles) { profile in
                        ProfilePillButton(
                            name: profile.name,
                            isActive: profileManager.activeProfile?.id == profile.id
                        ) {
                            Task { await profileManager.applyProfile(profile) }
                        }
                    }

                    // Add button
                    Button {
                        showingNewProfile = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(MontrTheme.textSecondary)
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(MontrTheme.cardBackground)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .alert("New Profile", isPresented: $showingNewProfile) {
            TextField("Profile Name", text: $newProfileName)
            Button("Cancel", role: .cancel) { newProfileName = "" }
            Button("Create") {
                if !newProfileName.isEmpty {
                    Task {
                        _ = await profileManager.createProfile(name: newProfileName)
                        newProfileName = ""
                    }
                }
            }
        } message: {
            Text("Enter a name for the new profile")
        }
    }
}

// MARK: - Profile Pill Button

private struct ProfilePillButton: View {
    let name: String
    let isActive: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                }

                Text(name)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(isActive ? .black : MontrTheme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(
                        isActive
                            ? MontrTheme.teal
                            : (isHovering
                                ? MontrTheme.cardBackground
                                : MontrTheme.cardBackground.opacity(0.6)))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Empty Display State

private struct EmptyDisplayState: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "display.trianglebadge.exclamationmark")
                .font(.system(size: 28))
                .foregroundColor(MontrTheme.textSecondary)

            VStack(spacing: 4) {
                Text("No Displays Found")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(MontrTheme.textPrimary)

                Text("Connect an external display")
                    .font(.system(size: 11))
                    .foregroundColor(MontrTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(MontrTheme.cardBackground)
        )
    }
}

// MARK: - Preview

#Preview {
    PopoverContentView()
        .frame(width: 320, height: 420)
}
