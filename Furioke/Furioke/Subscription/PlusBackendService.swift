import Foundation

/// The app's calls to the Furioke backend's billing surface — both halves of
/// keeping Plus correct across storefronts:
///
/// - `register(jws:)` reports a verified StoreKit transaction so the shared
///   `subscriptions` row is written and the entitlement lifts the server gates
///   (and holds on the web) for this account.
/// - `fetchIsPlus()` reads the *unified* entitlement the backend derives from
///   that table across every provider. The on-device StoreKit entitlement only
///   knows about Apple purchases, so this is how iOS learns that the user is
///   already Plus from a web (Stripe) subscription — without it, a web
///   subscriber would still see the upgrade prompt in the app and could
///   double-subscribe.
///
/// Both authenticate with the user's Supabase bearer token. Failures are
/// non-fatal: registration is reconciled by App Store Server Notifications, and
/// a failed entitlement read just leaves the advisory flag unchanged.
struct PlusBackendService {
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
    guard var request = await authorizedRequest(path: "api/billing/apple/register") else {
      return
    }
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONEncoder().encode(RegisterRequest(jws: jws))
    _ = try? await URLSession.shared.data(for: request)
  }

  /// Read the unified Plus entitlement for the signed-in user. Returns `nil` on
  /// any failure (offline, auth, non-200) so the caller can leave its current
  /// value in place rather than flipping Plus off on a transient error.
  func fetchIsPlus() async -> Bool? {
    guard
      let request = await authorizedRequest(path: "api/billing/entitlement"),
      let (data, response) = try? await URLSession.shared.data(for: request),
      let http = response as? HTTPURLResponse, http.statusCode == 200,
      let decoded = try? JSONDecoder().decode(EntitlementResponse.self, from: data)
    else {
      return nil
    }
    return decoded.isPlus
  }

  /// A bearer-authenticated request to `path`, or nil when no valid token is
  /// available (signed out / refresh rejected).
  private func authorizedRequest(path: String) async -> URLRequest? {
    guard let token = try? await auth.validAccessToken() else { return nil }
    var request = URLRequest(url: baseURL.appendingPathComponent(path))
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    return request
  }
}

private struct RegisterRequest: Encodable {
  let jws: String
}

private struct EntitlementResponse: Decodable {
  let isPlus: Bool

  enum CodingKeys: String, CodingKey {
    case isPlus = "is_plus"
  }
}
