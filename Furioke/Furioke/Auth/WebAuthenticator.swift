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
    let scene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
    return scene?.keyWindow ?? ASPresentationAnchor()
  }
}
