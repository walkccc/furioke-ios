import AuthenticationServices
import CryptoKit
import UIKit

/// Drives the native Sign in with Apple flow: builds an `ASAuthorizationController`
/// request carrying the SHA-256 of a fresh nonce, presents it, and resolves the
/// returned Apple identity token together with the *raw* nonce. `AuthService`
/// hands both to `signInWithIdToken` / `linkIdentityWithIdToken` — Supabase
/// verifies the token's `nonce` claim against the hash of the raw value, which is
/// why the raw nonce must round-trip back out of here.
@MainActor
final class AppleSignInController: NSObject {
  /// The identity token (a JWT) plus the raw nonce used to derive the hashed nonce
  /// sent to Apple. Supabase needs the raw value to validate the token.
  struct Credential {
    let idToken: String
    let rawNonce: String
  }

  enum AppleSignInError: Error {
    case invalidCredential
    case missingIdentityToken
  }

  /// Held for the lifetime of one in-flight authorization; the continuation is
  /// resumed exactly once by the delegate callbacks.
  private var continuation: CheckedContinuation<Credential, Error>?
  private var currentNonce: String?

  /// Present the Apple sign-in sheet and resolve the identity token + raw nonce.
  /// Throws `ASAuthorizationError.canceled` when the user dismisses the sheet, so
  /// `AuthService` can keep cancellation silent.
  func requestCredential() async throws -> Credential {
    let nonce = Self.randomNonceString()
    currentNonce = nonce

    let request = ASAuthorizationAppleIDProvider().createRequest()
    request.requestedScopes = [.fullName, .email]
    request.nonce = Self.sha256(nonce)

    return try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
      let controller = ASAuthorizationController(authorizationRequests: [request])
      controller.delegate = self
      controller.presentationContextProvider = self
      controller.performRequests()
    }
  }

  // MARK: Nonce

  /// A URL-safe random string used as the OIDC nonce. Apple receives its SHA-256;
  /// Supabase receives the raw value to compare against the token's `nonce` claim.
  private static func randomNonceString(length: Int = 32) -> String {
    var bytes = [UInt8](repeating: 0, count: length)
    let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    precondition(status == errSecSuccess, "Unable to generate a secure nonce: \(status)")
    let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
    return String(bytes.map { charset[Int($0) % charset.count] })
  }

  private static func sha256(_ input: String) -> String {
    SHA256.hash(data: Data(input.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
  }
}

// MARK: - ASAuthorizationControllerDelegate

extension AppleSignInController: ASAuthorizationControllerDelegate {
  func authorizationController(
    controller _: ASAuthorizationController,
    didCompleteWithAuthorization authorization: ASAuthorization
  ) {
    defer { continuation = nil
      currentNonce = nil
    }
    guard
      let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
      let rawNonce = currentNonce
    else {
      continuation?.resume(throwing: AppleSignInError.invalidCredential)
      return
    }
    guard
      let tokenData = credential.identityToken,
      let idToken = String(data: tokenData, encoding: .utf8)
    else {
      continuation?.resume(throwing: AppleSignInError.missingIdentityToken)
      return
    }
    continuation?.resume(returning: Credential(idToken: idToken, rawNonce: rawNonce))
  }

  func authorizationController(
    controller _: ASAuthorizationController,
    didCompleteWithError error: Error
  ) {
    continuation?.resume(throwing: error)
    continuation = nil
    currentNonce = nil
  }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AppleSignInController: ASAuthorizationControllerPresentationContextProviding {
  func presentationAnchor(for _: ASAuthorizationController) -> ASPresentationAnchor {
    // Mirrors `WebAuthenticator`: anchor to the active foreground window scene; the
    // absence of one while presenting is a programmer error, not a runtime branch.
    let windowScenes = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
    let scene = windowScenes.first { $0.activationState == .foregroundActive }
      ?? windowScenes.first
    guard let scene else {
      preconditionFailure("No window scene available to anchor the Apple sign-in sheet")
    }
    return scene.keyWindow ?? ASPresentationAnchor(windowScene: scene)
  }
}
