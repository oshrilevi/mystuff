import SwiftUI

struct RootView: View {
    @EnvironmentObject var authService: GoogleAuthService
    @State private var session: Session?
    @State private var setupTakingTooLong = false
    @State private var initialLoadComplete = false

    var body: some View {
        Group {
            if !authService.isSignedIn {
                SignInView()
            } else if session == nil {
                ProgressView("Setting up…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear { session = Session(authService: authService) }
            } else if let session = session, session.appState.spreadsheetId == nil, session.appState.bootstrapError == nil {
                ZStack {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text(session.appState.bootstrapStep.isEmpty ? (session.appState.isBootstrapping ? "Creating your sheet…" : "Loading…") : session.appState.bootstrapStep)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("This may take up to a minute.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Button("Sign out") {
                            authService.signOut()
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                        .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if setupTakingTooLong {
                        VStack(spacing: 20) {
                            Text("This is taking longer than expected")
                                .font(.headline)
                                .multilineTextAlignment(.center)
                            Text("Setup may be stuck. You can retry or sign out and try again.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            HStack(spacing: 12) {
                                Button("Retry") {
                                    setupTakingTooLong = false
                                    session.appState.bootstrapError = nil
                                    Task { await session.bootstrap() }
                                }
                                .buttonStyle(.borderedProminent)
                                Button("Sign out") {
                                    setupTakingTooLong = false
                                    authService.signOut()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(24)
                        .background(.regularMaterial)
                        .cornerRadius(12)
                        .padding(40)
                    }
                }
                .task(id: "timeout") {
                    setupTakingTooLong = false
                    try? await Task.sleep(nanoseconds: 15_000_000_000) // 15 seconds
                    if session.appState.spreadsheetId == nil, session.appState.bootstrapError == nil {
                        setupTakingTooLong = true
                    }
                }
            } else if let session = session, session.appState.bootstrapError != nil {
                VStack(spacing: 16) {
                    Text("Setup failed")
                        .font(.headline)
                    Text(session.appState.bootstrapError ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Retry") {
                        session.appState.bootstrapError = nil
                        Task { await session.bootstrap() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let session = session {
                ZStack {
                    MainTabView()
                        .environmentObject(session)
                        .opacity(initialLoadComplete ? 1 : 0)
                    LoadingView()
                        .opacity(initialLoadComplete ? 0 : 1)
                        .allowsHitTesting(!initialLoadComplete)
                }
                .animation(.easeIn(duration: 0.35), value: initialLoadComplete)
                .task(id: session.appState.spreadsheetId) {
                    guard session.appState.spreadsheetId != nil else { return }
                    initialLoadComplete = false
                    await session.categories.load()
                    await session.locations.load()
                    await session.inventory.refresh()
                    initialLoadComplete = true
                }
            }
        }
        .animation(.easeInOut, value: authService.isSignedIn)
        .task(id: session != nil) {
            guard let session = session else { return }
            if session.appState.spreadsheetId == nil, session.appState.bootstrapError == nil {
                await session.bootstrap()
            }
        }
        .onChange(of: authService.isSignedIn) { _, signedIn in
            if !signedIn { session = nil }
        }
    }
}
