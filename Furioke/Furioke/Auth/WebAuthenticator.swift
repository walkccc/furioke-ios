import AuthenticationServices
import UIKit

/// Presents an OAuth URL in `ASWebAuthenticationSession` and resolves the custom-
/// scheme callback. supabase-swift builds the sign-in URL and exchanges the
/// callback for a session; this type owns only the presentation and the anchor.
@MainActor
final class WebAuthenticator: NSObject, ASWebAuthenticationPresentationContextProviding {
  enum WebAuthError: Error {
    case missingCallbackURL
    case failedToStart
  }

  /// Held for the lifetime of the in-flight presentation; ASWebAuthenticationSession
  /// is otherwise deallocated before the user finishes.
  private var session: ASWebAuthenticationSession?

  func authenticate(url: URL, callbackScheme: String) async throws -> URL {
    try await withCheckedThrowingContinuation { continuation in
      let session = ASWebAuthenticationSession(
        url: url,
        callbackURLScheme: callbackScheme
      ) { callbackURL, error in
        if let error {
          continuation.resume(throwing: error)
        } else if let callbackURL {
          continuation.resume(returning: callbackURL)
        } else {
          continuation.resume(throwing: WebAuthError.missingCallbackURL)
        }
      }
      session.presentationContextProvider = self
      session.prefersEphemeralWebBrowserSession = false
      self.session = session
      if !session.start() {
        continuation.resume(throwing: WebAuthError.failedToStart)
      }
    }
  }

  func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
    let windowScenes = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
    let scene = windowScenes.first { $0.activationState == .foregroundActive }
      ?? windowScenes.first
    guard let scene else {
      // ASWebAuthenticationSession only requests an anchor while presenting, which
      // requires a live window scene; the absence of one is a programmer error, not
      // a runtime condition to paper over with a deprecated empty `UIWindow()`.
      preconditionFailure("No window scene available to anchor the auth session")
    }
    // Prefer the existing key window; if none is up yet, anchor a fresh window to
    // the scene rather than the deprecated `UIWindow()` (removed in iOS 26).
    return scene.keyWindow ?? ASPresentationAnchor(windowScene: scene)
  }
}
