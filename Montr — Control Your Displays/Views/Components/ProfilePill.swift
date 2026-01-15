import SwiftUI

/// Pill-shaped button for a profile
struct ProfilePill: View {
    let profile: Profile
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(profile.name)
                .font(.caption)
                .fontWeight(isActive ? .semibold : .regular)
                .foregroundColor(isActive ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isActive ? Color.accentColor : Color.secondary.opacity(0.15))
                .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    HStack(spacing: 8) {
        ProfilePill(
            profile: Profile(name: "Work"),
            isActive: true
        ) {}

        ProfilePill(
            profile: Profile(name: "Movie"),
            isActive: false
        ) {}

        ProfilePill(
            profile: Profile(name: "Night"),
            isActive: false
        ) {}
    }
    .padding()
}
