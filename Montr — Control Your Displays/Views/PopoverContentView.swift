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
                    // Displays
                    if displayManager.displays.isEmpty {
                        EmptyDisplayState()
                    } else {
                        ForEach(displayManager.displays) { display in
                            DisplayCard(display: display)
                        }
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
            Button {
                NotificationCenter.default.post(name: .openMontrSettings, object: nil)
            } label: {
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
                    .fill(displayManager.displays.isEmpty ? MontrTheme.textSecondary : MontrTheme.connectedGreen)
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
            .foregroundColor(brightnessController.quickDimEnabled ? .black : MontrTheme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(brightnessController.quickDimEnabled ? MontrTheme.teal : Color.clear)
                    .overlay(
                        Capsule()
                            .stroke(brightnessController.quickDimEnabled ? Color.clear : MontrTheme.textSecondary.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Display Card

private struct DisplayCard: View {
    let display: Display

    @StateObject private var brightnessController = BrightnessController.shared
    @State private var brightness: Double = 100

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row
            HStack(spacing: 8) {
                // Connected indicator
                Circle()
                    .fill(MontrTheme.connectedGreen)
                    .frame(width: 8, height: 8)

                // Display name
                Text(display.displayName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(MontrTheme.textPrimary)

                Spacer()

                // Badge
                Text(display.controlMethodBadge)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(MontrTheme.teal)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(MontrTheme.teal, lineWidth: 1)
                    )
            }

            // Brightness slider
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
                            .frame(width: max(6, geometry.size.width * (brightness / 100)), height: 6)

                        // Thumb
                        Circle()
                            .fill(.white)
                            .frame(width: 14, height: 14)
                            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                            .offset(x: max(0, min(geometry.size.width - 14, (geometry.size.width - 14) * (brightness / 100))))
                    }
                    .frame(height: 20)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { gesture in
                                let newValue = min(max(0, gesture.location.x / geometry.size.width * 100), 100)
                                brightness = newValue
                            }
                            .onEnded { _ in
                                Task {
                                    await brightnessController.setBrightness(for: display, value: Int(brightness))
                                }
                            }
                    )
                }
                .frame(height: 20)

                Text("\(Int(brightness))%")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(MontrTheme.textPrimary)
                    .frame(width: 40, alignment: .trailing)
                    .monospacedDigit()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(MontrTheme.cardBackground)
        )
        .onAppear {
            brightness = Double(brightnessController.getBrightness(for: display))
        }
        .onChange(of: brightnessController.displayBrightness[display.stableIdentifier]) { _, newValue in
            if let newValue {
                brightness = Double(newValue)
            }
        }
    }
}

// MARK: - Night Shift Section

private struct NightShiftSection: View {
    @StateObject private var colorTempController = ColorTemperatureController.shared
    @State private var temperature: Double = 5625

    private let minTemp: Double = 2700
    private let maxTemp: Double = 6500

    private var normalizedValue: Double {
        (temperature - minTemp) / (maxTemp - minTemp)
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
                Toggle("", isOn: Binding(
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
                ))
                .toggleStyle(TealToggleStyle())
                .labelsHidden()
            }

            // Temperature slider
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Gradient track
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [MontrTheme.warmOrange, Color(white: 0.9)],
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
                        .offset(x: max(0, min(geometry.size.width - 18, (geometry.size.width - 18) * normalizedValue)))
                }
                .frame(height: 24)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            guard colorTempController.isEnabled else { return }
                            let normalized = min(max(0, gesture.location.x / geometry.size.width), 1)
                            temperature = minTemp + normalized * (maxTemp - minTemp)
                        }
                        .onEnded { _ in
                            Task {
                                await colorTempController.setGlobalTemperature(Int(temperature))
                            }
                        }
                )
            }
            .frame(height: 24)

            // Temperature labels
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
                    .fill(isActive ? MontrTheme.teal : (isHovering ? MontrTheme.cardBackground : MontrTheme.cardBackground.opacity(0.6)))
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
