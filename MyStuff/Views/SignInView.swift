import SwiftUI

struct SignInView: View {
    @EnvironmentObject var authService: GoogleAuthService
    @State private var isSigningIn = false

    var body: some View {
        VStack(spacing: 24) {
            Text("Oshri's World")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Track everything you own")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("The app may sign you in automatically if you’ve signed in before.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            if let error = authService.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            Button {
                isSigningIn = true
                Task {
                    await authService.signIn()
                    isSigningIn = false
                }
            } label: {
                HStack(spacing: 8) {
                    if isSigningIn {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.white)
                    } else {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                        Text("Sign in with Google")
                    }
                }
                .frame(maxWidth: 280)
                .padding(.vertical, 12)
                .background(Color.primary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(isSigningIn)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
