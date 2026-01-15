import SwiftUI

/// Custom brightness slider with sun icon and percentage
struct BrightnessSlider: View {
    @Binding var value: Double
    let displayId: String
    var onValueChanged: ((Double) -> Void)?

    @State private var isDragging = false

    var body: some View {
        HStack(spacing: 8) {
            // Sun icon (dimmer when brightness is low)
            Image(systemName: value < 50 ? "sun.min" : "sun.max")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .opacity(0.3 + (value / 100) * 0.7)

            // Slider
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Track background
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 6)

                    // Filled track
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accentColor)
                        .frame(width: geometry.size.width * (value / 100), height: 6)

                    // Thumb
                    Circle()
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                        .frame(width: 14, height: 14)
                        .offset(x: (geometry.size.width - 14) * (value / 100))
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            isDragging = true
                            let newValue = min(max(0, gesture.location.x / geometry.size.width * 100), 100)
                            value = newValue
                        }
                        .onEnded { _ in
                            isDragging = false
                            onValueChanged?(value)
                        }
                )
            }
            .frame(height: 20)

            // Percentage label
            Text("\(Int(value))%")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 36, alignment: .trailing)
                .monospacedDigit()
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        BrightnessSlider(value: .constant(75), displayId: "test")
        BrightnessSlider(value: .constant(25), displayId: "test")
        BrightnessSlider(value: .constant(100), displayId: "test")
    }
    .padding()
    .frame(width: 280)
}
