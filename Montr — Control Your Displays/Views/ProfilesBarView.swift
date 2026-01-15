import SwiftUI

/// Horizontal bar of profile buttons
struct ProfilesBarView: View {
    @StateObject private var profileManager = ProfileManager.shared
    @State private var showingNewProfile = false
    @State private var newProfileName = ""

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(profileManager.profiles) { profile in
                    ProfilePill(
                        profile: profile,
                        isActive: profileManager.activeProfile?.id == profile.id
                    ) {
                        Task {
                            await profileManager.applyProfile(profile)
                        }
                    }
                }

                // Add new profile button
                Button {
                    showingNewProfile = true
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
        }
        .alert("New Profile", isPresented: $showingNewProfile) {
            TextField("Profile Name", text: $newProfileName)
            Button("Cancel", role: .cancel) {
                newProfileName = ""
            }
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

// MARK: - Preview

#Preview {
    ProfilesBarView()
        .padding()
}
