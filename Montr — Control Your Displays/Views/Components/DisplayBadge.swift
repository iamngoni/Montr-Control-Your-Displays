import SwiftUI

/// Badge showing the display control method (DDC/CI, Software, System)
struct DisplayBadge: View {
    let text: String

    private var badgeColor: Color {
        switch text {
        case "DDC/CI":
            return .green
        case "Software":
            return .orange
        case "System":
            return .blue
        default:
            return .gray
        }
    }

    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundColor(badgeColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(badgeColor.opacity(0.15))
            .cornerRadius(4)
    }
}

// MARK: - Preview

#Preview {
    HStack(spacing: 8) {
        DisplayBadge(text: "DDC/CI")
        DisplayBadge(text: "Software")
        DisplayBadge(text: "System")
    }
    .padding()
}
