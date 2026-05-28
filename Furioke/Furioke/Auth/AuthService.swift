import AuthenticationServices
import Observation
import Supabase

/// Owns the iOS Supabase session: Google OAuth sign-in via
/// `ASWebAuthenticationSession`, Keychain-backed persistence, transparent refresh,
/// and sign-out. Injected at the root; `RootView` renders sign-in vs.
/// the tab bar from `state`. Sessions are independent of the web app — sign-out
/// uses local scope so the user's browser session is untouched.
@Observable
@MainActor
final class AuthService {
  enum State: Equatable {
    case loading
    case signedOut
    case signedIn(userID: UUID)
  }

  private(set) var state: State = .loading

  /// Surfaced to the sign-in view for genuine failures. User cancellation is
  /// intentionally silent (no value set).
  private(set) var lastSignInError: String?

  /// Cross-subsystem teardown for explicit sign-out: purge per-user SwiftData
  /// entities, clear the in-memory Spotify session, and forget MusicKit
  /// authorization. The composition root wires this once those subsystems land;
  /// auth must not import them. Not invoked on forced sign-out from a refresh
  /// failure — that only clears credentials, leaving cached data for the same
  /// user's next sign-in.
  var onSignOutCleanup: (@MainActor () async -> Void)?

  let client: SupabaseClient
  private let webAuthenticator = WebAuthenticator()
  /// Mutated only on the main actor (in `observeAuthState`); read in the
  /// nonisolated `deinit`, which runs after the last reference drops, so there is
  /// no concurrent access. `Task` is `Sendable`, so cancelling it is safe anywhere.
  @ObservationIgnored private var authStateTask: Task<Void, Never>?

  init() {
    client = SupabaseClient(
      supabaseURL: SupabaseConfig.url,
      supabaseKey: SupabaseConfig.anonKey,
      options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
          storage: KeychainSessionStore(),
          redirectToURL: SupabaseConfig.redirectURL,
          flowType: .pkce
        )
      )
    )
    observeAuthState()
  }

  deinit {
    authStateTask?.cancel()
  }

  /// Subscribing emits `.initialSession` immediately — restoring (and refreshing)
  /// any Keychain session on cold start — then streams subsequent changes.
  private func observeAuthState() {
    authStateTask = Task { [weak self] in
      guard let client = self?.client else { return }
      // Bind `self` weakly per iteration so it is not retained across the
      // suspension between events — otherwise the never-ending stream would keep
      // `AuthService` alive forever and `deinit` would never fire.
      for await(event, session) in client.auth.authStateChanges {
        guard !Task.isCancelled, let self else { break }
        self.apply(event: event, session: session)
      }
    }
  }

  private func apply(event: AuthChangeEvent, session: Session?) {
    switch event {
    case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
      state = session.map { .signedIn(userID: $0.user.id) } ?? .signedOut
    case .signedOut, .userDeleted:
      state = .signedOut
    case .passwordRecovery, .mfaChallengeVerified:
      break
    }
  }

  // MARK: Sign-in

  func signInWithGoogle() async {
    lastSignInError = nil
    do {
      try await client.auth.signInWithOAuth(
        provider: .google,
        redirectTo: SupabaseConfig.redirectURL
      ) { [webAuthenticator] url in
        // supabase-swift hands us the authorize URL; we present it and return the
        // callback URL, which it then exchanges for a session (PKCE), writing the
        // tokens through to the Keychain. `apply` flips `state` on `.signedIn`.
        try await webAuthenticator.authenticate(
          url: url,
          callbackScheme: SupabaseConfig.redirectURL.scheme!
        )
      }
    } catch {
      guard !isUserCancellation(error) else { return }
      lastSignInError = error.localizedDescription
    }
  }

  private func isUserCancellation(_ error: Error) -> Bool {
    if let authSessionError = error as? ASWebAuthenticationSessionError {
      return authSessionError.code == .canceledLogin
    }
    return error is CancellationError
  }

  // MARK: Token access (refresh-on-expiry)

  /// The seam backend requests use to obtain a valid bearer token. supabase-swift
  /// refreshes transparently when the access token is at/near expiry. A rejected
  /// refresh token clears the session and drops to the sign-in surface; transient
  /// failures (network, 5xx) are rethrown without signing the user out.
  func validAccessToken() async throws -> String {
    do {
      return try await client.auth.session.accessToken
    } catch {
      if isRefreshTokenRejected(error) {
        await clearSession(purgeUserData: false)
      }
      throw error
    }
  }

  private func isRefreshTokenRejected(_ error: Error) -> Bool {
    guard let authError = error as? AuthError else { return false }
    switch authError {
    case .sessionMissing:
      return true
    case let .api(_, _, _, response):
      return [400, 401, 403].contains(response.statusCode)
    default:
      return false
    }
  }

  // MARK: Sign-out

  func signOut() async {
    await clearSession(purgeUserData: true)
  }

  private func clearSession(purgeUserData: Bool) async {
    // Local scope only: must not invalidate the user's web session. The session
    // is removed from the Keychain before the network logout call, so credentials
    // are cleared even if that call fails.
    try? await client.auth.signOut(scope: .local)
    if purgeUserData {
      await onSignOutCleanup?()
    }
    state = .signedOut
  }
}
