import SwiftUI

/// Row view for a single display with brightness control
struct DisplayRowView: View {
    let display: Display

    @StateObject private var brightnessController = BrightnessController.shared
    @State private var brightness: Double = 75

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Display name and badge
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(display.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    if let subtitle = display.subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                DisplayBadge(text: display.controlMethodBadge)
            }

            // Brightness slider
            BrightnessSlider(
                value: $brightness,
                displayId: display.stableIdentifier,
                onValueChanged: { newValue in
                    Task {
                        await brightnessController.setBrightness(for: display, value: Int(newValue))
                    }
                }
            )

            // Contrast slider (if enabled and supported)
            if SettingsManager.shared.contrastEnabled && display.supportsDDC && !display.isBuiltIn {
                ContrastSlider(display: display)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
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

// MARK: - Contrast Slider

private struct ContrastSlider: View {
    let display: Display

    @StateObject private var brightnessController = BrightnessController.shared
    @State private var contrast: Double = 75

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.lefthalf.filled")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            Slider(value: $contrast, in: 0...100, step: 1) { _ in
                Task {
                    await brightnessController.setContrast(for: display, value: Int(contrast))
                }
            }
            .controlSize(.small)

            Text("\(Int(contrast))%")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
        .onAppear {
            contrast = Double(brightnessController.getContrast(for: display))
        }
    }
}

// MARK: - Preview

#Preview {
    DisplayRowView(display: Display(
        id: 1,
        vendorName: "Dell",
        modelName: "U2722D",
        isBuiltIn: false,
        supportsDDC: true,
        nativeResolution: CGSize(width: 2560, height: 1440),
        currentResolution: CGSize(width: 2560, height: 1440),
        connectionType: .usbc,
        customName: "Work Monitor"
    ))
    .frame(width: 300)
    .padding()
}
