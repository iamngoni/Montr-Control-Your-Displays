import SwiftUI

/// Color temperature wheel/spectrum picker
struct ColorTemperatureWheelView: View {
    @Binding var temperature: Int
    let isEnabled: Bool

    @State private var isDragging = false

    // Temperature range
    private let minTemp = 2700
    private let maxTemp = 6500

    private var normalizedValue: Double {
        Double(temperature - minTemp) / Double(maxTemp - minTemp)
    }

    var body: some View {
        VStack(spacing: 8) {
            // Gradient bar with indicator
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Temperature gradient
                    LinearGradient(
                        gradient: Gradient(colors: temperatureColors),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .cornerRadius(6)
                    .opacity(isEnabled ? 1.0 : 0.5)

                    // Position indicator
                    Circle()
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                        .frame(width: 18, height: 18)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                        )
                        .offset(x: (geometry.size.width - 18) * normalizedValue)
                }
                .frame(height: 24)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            guard isEnabled else { return }
                            isDragging = true
                            let normalized = min(max(0, gesture.location.x / geometry.size.width), 1)
                            temperature = minTemp + Int(normalized * Double(maxTemp - minTemp))
                        }
                        .onEnded { _ in
                            isDragging = false
                        }
                )
            }
            .frame(height: 24)

            // Presets
            HStack(spacing: 4) {
                ForEach(TemperaturePreset.allCases.filter { $0 != .off }, id: \.self) { preset in
                    PresetButton(
                        preset: preset,
                        isSelected: abs(temperature - preset.kelvin) < 200,
                        isEnabled: isEnabled
                    ) {
                        temperature = preset.kelvin
                    }
                }
            }
        }
    }

    // MARK: - Temperature Colors

    private var temperatureColors: [Color] {
        let steps = 10
        return (0...steps).map { step in
            let temp = minTemp + (maxTemp - minTemp) * step / steps
            return colorForTemperature(temp)
        }
    }

    private func colorForTemperature(_ kelvin: Int) -> Color {
        let rgb = kelvinToRGB(kelvin: kelvin)
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    private func kelvinToRGB(kelvin: Int) -> (red: Double, green: Double, blue: Double) {
        let temp = Double(max(1000, min(40000, kelvin))) / 100.0

        var red: Double
        var green: Double
        var blue: Double

        // Calculate red
        if temp <= 66 {
            red = 255
        } else {
            red = temp - 60
            red = 329.698727446 * pow(red, -0.1332047592)
            red = max(0, min(255, red))
        }

        // Calculate green
        if temp <= 66 {
            green = temp
            green = 99.4708025861 * log(green) - 161.1195681661
            green = max(0, min(255, green))
        } else {
            green = temp - 60
            green = 288.1221695283 * pow(green, -0.0755148492)
            green = max(0, min(255, green))
        }

        // Calculate blue
        if temp >= 66 {
            blue = 255
        } else if temp <= 19 {
            blue = 0
        } else {
            blue = temp - 10
            blue = 138.5177312231 * log(blue) - 305.0447927307
            blue = max(0, min(255, blue))
        }

        return (red / 255.0, green / 255.0, blue / 255.0)
    }
}

// MARK: - Preset Button

private struct PresetButton: View {
    let preset: TemperaturePreset
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(preset.name)
                .font(.caption2)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.5)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        ColorTemperatureWheelView(temperature: .constant(4000), isEnabled: true)
        ColorTemperatureWheelView(temperature: .constant(6500), isEnabled: false)
    }
    .padding()
    .frame(width: 280)
}
