import SwiftUI
import GoogleSignIn

struct UserAvatarMenuView: View {
    @EnvironmentObject var authService: GoogleAuthService
    @State private var showSignOut = false

    private let size: CGFloat = 32

    var body: some View {
        Button {
            showSignOut = true
        } label: {
            avatarImage
        }
        .buttonStyle(.plain)
        .confirmationDialog("Account", isPresented: $showSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) {
                authService.signOut()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(authService.currentUser?.profile?.email ?? "Signed in")
        }
    }

    @ViewBuilder
    private var avatarImage: some View {
        Group {
            if let url = authService.currentUser?.profile?.imageURL(withDimension: UInt(size * 2)),
               authService.currentUser?.profile?.hasImage == true {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure, .empty:
                        placeholderContent
                    @unknown default:
                        placeholderContent
                    }
                }
            } else {
                placeholderContent
            }
        }
        .frame(width: size, height: size)
        .mask(Circle())
        .overlay(
            Circle()
                .strokeBorder(.bar.opacity(0.5), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 1)
        .contentShape(Circle())
    }

    private var placeholderContent: some View {
        Circle()
            .fill(.secondary.opacity(0.3))
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(.secondary)
            )
    }
}
