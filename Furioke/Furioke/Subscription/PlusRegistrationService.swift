import Foundation

/// Reports a verified StoreKit transaction to the Furioke backend so the
/// shared `subscriptions` row is written and the entitlement lifts the
/// server-enforced AI cap (and the flashcard cap) for this user on every
/// device — web included.
///
/// The on-device StoreKit entitlement is the source of truth for *UI* gating
/// (instant, offline); this call is what makes the entitlement *enforceable*.
/// The transaction is bound to the Supabase user through its `appAccountToken`
/// (set at purchase to the user id), so the backend resolves the account from
/// the signed transaction itself; the bearer token is sent too as a second
/// signal. Failures are non-fatal: App Store Server Notifications reconcile the
/// row independently, and the next launch re-registers the current entitlement.
struct PlusRegistrationService {
  private let auth: AuthService
  private let baseURL: URL

  init(auth: AuthService, baseURL: URL = BackendConfig.apiBaseURL) {
    self.auth = auth
    self.baseURL = baseURL
  }

  /// POST the transaction's signed JWS representation to the register route.
  /// `jws` is `VerificationResult.jwsRepresentation` — the App Store-signed
  /// payload the backend re-verifies against Apple's certificate chain.
  func register(jws: String) async {
    guard let token = try? await auth.validAccessToken() else { return }
    var request = URLRequest(
      url: baseURL.appendingPathComponent("api/billing/apple/register")
    )
    request.httpMethod = "POST"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONEncoder().encode(RegisterRequest(jws: jws))
    _ = try? await URLSession.shared.data(for: request)
  }
}

private struct RegisterRequest: Encodable {
  let jws: String
}
