import Foundation
import SwiftUI
import GoogleSignIn

#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
public final class GoogleAuthService: ObservableObject {
    @Published public private(set) var isSignedIn = false
    @Published public private(set) var currentUser: GIDGoogleUser?
    @Published public private(set) var errorMessage: String?

    private let scopes = [
        "https://www.googleapis.com/auth/spreadsheets",
        "https://www.googleapis.com/auth/drive.file"
    ]

    public init() {
        Task { await restorePreviousSignIn() }
    }

    public func signIn() async {
        errorMessage = nil
        if let clientID = Bundle.main.infoDictionary?["GIDClientID"] as? String,
           clientID.contains("YOUR_") {
            errorMessage = "Google Client ID not set. Open MyStuff/Info.plist and replace YOUR_IOS_CLIENT_ID with your OAuth Client ID from Google Cloud Console. See README for step-by-step instructions."
            return
        }
        do {
            #if os(macOS)
            guard let window = await getKeyWindow() else {
                errorMessage = "No window available"
                return
            }
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: window)
            #else
            guard let windowScene = await getWindowScene(),
                  let rootVC = await getRootViewController(from: windowScene) else {
                errorMessage = "No window scene available"
                return
            }
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootVC)
            #endif
            let user = result.user
            #if os(macOS)
            let additionalScopes = scopes.filter { user.grantedScopes?.contains($0) != true }
            if !additionalScopes.isEmpty, let window = await getKeyWindow() {
                _ = try await user.addScopes(additionalScopes, presenting: window)
            }
            #else
            let additionalScopes = scopes.filter { user.grantedScopes?.contains($0) != true }
            if !additionalScopes.isEmpty, let rootVC = await getRootViewController(from: await getWindowScene()!) {
                _ = try await user.addScopes(additionalScopes, presenting: rootVC)
            }
            #endif
            currentUser = user
            isSignedIn = true
        } catch {
            let msg = error.localizedDescription
            if msg.lowercased().contains("client secret") {
                errorMessage = "Wrong credential type. Use an iOS OAuth Client ID (not Web or Desktop). In Google Cloud Console → Credentials, create an OAuth 2.0 Client ID with application type iOS. The same iOS client works for both iPhone and Mac. Then put that Client ID in Info.plist."
            } else {
                errorMessage = msg
            }
        }
    }

    public func signOut() {
        GIDSignIn.sharedInstance.signOut()
        currentUser = nil
        isSignedIn = false
        errorMessage = nil
    }

    public func restorePreviousSignIn() async {
        do {
            let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
            currentUser = user
            isSignedIn = user != nil
        } catch {
            currentUser = nil
            isSignedIn = false
        }
    }

    public func getAccessToken() async throws -> String {
        guard let user = currentUser else { throw AuthError.notSignedIn }
        do {
            let refreshedUser = try await user.refreshTokensIfNeeded()
            // Keep the latest user instance so any refreshed credentials are retained.
            currentUser = refreshedUser
            let tokenString = refreshedUser.accessToken.tokenString
            guard !tokenString.isEmpty else { throw AuthError.noToken }
            return tokenString
        } catch {
            throw AuthError.tokenRefreshFailed(error.localizedDescription)
        }
    }

    #if os(macOS)
    private func getKeyWindow() async -> NSWindow? {
        NSApplication.shared.windows.first { $0.isKeyWindow }
    }
    #else
    private func getWindowScene() async -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }

    private func getRootViewController(from windowScene: UIWindowScene) async -> UIViewController? {
        windowScene.windows.first { $0.isKeyWindow }?.rootViewController
    }
    #endif
}

public enum AuthError: LocalizedError {
    case notSignedIn
    case noToken
    case tokenRefreshFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Not signed in"
        case .noToken: return "No access token"
        case .tokenRefreshFailed(let message): return "Unable to refresh Google session: \(message)"
        }
    }
}
