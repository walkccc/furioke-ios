import AuthenticationServices
import Observation
import Supabase

/// Owns the iOS Supabase session. The app is guest-first: when no session is
/// restored on cold start it bootstraps a real but **anonymous** session so the
/// reading/playback experience works without an account, mirroring the web's
/// "try without signing in". Sign in with Apple (native, id-token) and Google
/// OAuth upgrade a guest in place via `linkIdentity`, preserving the `user_id`
/// (and any connected provider tokens). Reserved features — translation, the
/// saved-song library, flashcards — gate on a *permanent* account through
/// `requirePermanentAccount()`. Sessions are independent of the web app; sign-out
/// uses local scope and drops back to a fresh guest, never a sign-in wall.
@Observable
@MainActor
final class AuthService {
  enum State: Equatable {
    case loading
    /// A real but anonymous Supabase session (`is_anonymous == true`).
    case guest(userID: UUID)
    /// A permanent account.
    case signedIn(userID: UUID)
  }

  private(set) var state: State = .loading

  /// Display-only identity for a *permanent* user, captured from the in-memory
  /// session (no network fetch). Nil for a guest or while signed out. Read-only.
  private(set) var userEmail: String?

  /// Surfaced to the sign-in prompt for genuine failures. User cancellation is
  /// intentionally silent (no value set).
  private(set) var lastSignInError: String?

  /// Set when the anonymous bootstrap fails for a non-cancellation reason so the
  /// loading surface can offer a retry instead of spinning forever.
  private(set) var bootstrapFailed = false

  /// Drives the shared in-app sign-in prompt. Reserved-feature gates and the
  /// Settings "Sign in" affordance flip this; a top-level view binds a sheet to
  /// it. Cleared automatically once a permanent session is applied.
  var isSignInPromptPresented = false

  /// Cross-subsystem teardown for explicit sign-out: purge per-user SwiftData
  /// entities, clear the in-memory Spotify session, and forget MusicKit
  /// authorization. Wired by the composition root; auth must not import them. Runs
  /// before the post-sign-out guest session is established so the guest never
  /// inherits the prior user's cached data.
  var onSignOutCleanup: (@MainActor () async -> Void)?

  let client: SupabaseClient
  private let webAuthenticator = WebAuthenticator()
  private let appleSignIn = AppleSignInController()
  /// Mutated only on the main actor; read in the nonisolated `deinit` after the
  /// last reference drops, so there is no concurrent access.
  @ObservationIgnored private var authStateTask: Task<Void, Never>?
  /// Guards against launching more than one anonymous bootstrap at a time.
  @ObservationIgnored private var bootstrapTask: Task<Void, Never>?

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

  // MARK: Identity accessors

  /// The current session's user id regardless of guest vs. permanent — the id
  /// that scopes per-user rows that a guest is allowed to own (reading overrides,
  /// the lyric runtime). Nil only while loading with no session.
  var sessionUserID: UUID? {
    switch state {
    case let .guest(userID), let .signedIn(userID): userID
    case .loading: nil
    }
  }

  /// True only for a permanent account. The gate for reserved features.
  var isSignedIn: Bool {
    if case .signedIn = state { return true }
    return false
  }

  /// True for an anonymous guest session.
  var isGuest: Bool {
    if case .guest = state { return true }
    return false
  }

  // MARK: Reserved-feature gate

  /// The single seam reserved features call before acting. Returns `true` for a
  /// permanent account; otherwise presents the in-app sign-in prompt and returns
  /// `false` so the caller skips the action.
  @discardableResult
  func requirePermanentAccount() -> Bool {
    if isSignedIn { return true }
    presentSignInPrompt()
    return false
  }

  /// Opens the shared sign-in prompt (also used by the Settings "Sign in" row).
  func presentSignInPrompt() {
    lastSignInError = nil
    isSignInPromptPresented = true
  }

  // MARK: Session observation

  /// Subscribing emits `.initialSession` immediately — restoring any Keychain
  /// session on cold start — then streams subsequent changes.
  private func observeAuthState() {
    authStateTask = Task { [weak self] in
      guard let client = self?.client else { return }
      for await (event, session) in client.auth.authStateChanges {
        guard !Task.isCancelled, let self else { break }
        apply(event: event, session: session)
      }
    }
  }

  private func apply(event: AuthChangeEvent, session: Session?) {
    switch event {
    case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
      if let session {
        let userID = session.user.id
        if session.user.isAnonymous {
          state = .guest(userID: userID)
          userEmail = nil
        } else {
          state = .signedIn(userID: userID)
          userEmail = session.user.email
          // A reserved-feature action that triggered the prompt can now proceed.
          isSignInPromptPresented = false
        }
        bootstrapFailed = false
      } else {
        // No session to restore — become a guest.
        ensureGuestSession()
      }
    case .signedOut, .userDeleted:
      userEmail = nil
      ensureGuestSession()
    case .passwordRecovery, .mfaChallengeVerified:
      break
    }
  }

  // MARK: Anonymous bootstrap

  /// Establish an anonymous guest session when none exists. Idempotent: a second
  /// call while one is in flight is a no-op. The `authStateChanges` stream applies
  /// the resulting session (flipping `state` to `.guest`); on failure we mark
  /// `bootstrapFailed` so the loading surface can offer a retry rather than wedge.
  private func ensureGuestSession() {
    guard bootstrapTask == nil else { return }
    bootstrapTask = Task { [weak self] in
      defer { self?.bootstrapTask = nil }
      do {
        _ = try await self?.client.auth.signInAnonymously()
        self?.bootstrapFailed = false
      } catch {
        // Provider disabled, CAPTCHA / rate limit, or offline. Don't loop; let the
        // UI retry (and a later launch retries automatically).
        self?.bootstrapFailed = true
      }
    }
  }

  /// Re-attempt the anonymous bootstrap after a failure (driven by the loading
  /// surface's retry affordance).
  func retryBootstrap() {
    bootstrapFailed = false
    ensureGuestSession()
  }

  // MARK: Sign-in / upgrade

  /// Native Sign in with Apple. From a guest session this links the Apple identity
  /// to the existing anonymous user (preserving the `user_id` and connected
  /// provider tokens); otherwise it signs in fresh. User cancellation is silent.
  func signInWithApple() async {
    lastSignInError = nil
    do {
      let credential = try await appleSignIn.requestCredential()
      let oidc = OpenIDConnectCredentials(
        provider: .apple,
        idToken: credential.idToken,
        nonce: credential.rawNonce
      )
      if isGuest {
        do {
          _ = try await client.auth.linkIdentityWithIdToken(credentials: oidc)
          return
        } catch {
          // Link conflict (identity already belongs to another account) or linking
          // disabled — fall through to a plain sign-in to that account; the
          // orphaned guest session ages out via server cleanup.
        }
      }
      _ = try await client.auth.signInWithIdToken(credentials: oidc)
    } catch {
      guard !isUserCancellation(error) else { return }
      lastSignInError = error.localizedDescription
    }
  }

  /// Google OAuth sign-in. From a guest session this links the Google identity in
  /// place via the link-identity URL; otherwise it signs in fresh. Both present
  /// `ASWebAuthenticationSession`; cancellation is silent.
  func signInWithGoogle() async {
    lastSignInError = nil
    do {
      if isGuest {
        do {
          try await linkGoogleIdentity()
          return
        } catch {
          guard !isUserCancellation(error) else { return }
          // Link conflict / disabled — fall through to a normal Google sign-in.
        }
      }
      try await client.auth.signInWithOAuth(
        provider: .google,
        redirectTo: SupabaseConfig.redirectURL
      ) { [webAuthenticator] url in
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

  /// Link a Google identity to the current (anonymous) session: fetch the
  /// link-identity URL, present it, and exchange the callback for the upgraded
  /// session. A post-redirect conflict surfaces from `session(from:)` and is
  /// handled by the caller's fall-through.
  private func linkGoogleIdentity() async throws {
    let response = try await client.auth.getLinkIdentityURL(
      provider: .google,
      redirectTo: SupabaseConfig.redirectURL
    )
    let callbackURL = try await webAuthenticator.authenticate(
      url: response.url,
      callbackScheme: SupabaseConfig.redirectURL.scheme!
    )
    _ = try await client.auth.session(from: callbackURL)
  }

  private func isUserCancellation(_ error: Error) -> Bool {
    if let webError = error as? ASWebAuthenticationSessionError {
      return webError.code == .canceledLogin
    }
    if let appleError = error as? ASAuthorizationError {
      return appleError.code == .canceled
    }
    return error is CancellationError
  }

  // MARK: Token access (refresh-on-expiry)

  /// The seam backend requests use to obtain a valid bearer token. supabase-swift
  /// refreshes transparently near expiry. A rejected refresh token clears the
  /// session, which drops the user to a fresh guest via the auth-state stream;
  /// transient failures are rethrown without changing the session.
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

  /// Sign out of a permanent account and drop back to a guest session. The
  /// per-user cache purge runs *before* the new anonymous session is bootstrapped
  /// so the guest never inherits the prior user's data.
  func signOut() async {
    await clearSession(purgeUserData: true)
  }

  // MARK: Account deletion

  enum DeleteAccountError: Error { case requestFailed(Int) }

  /// Permanently delete the signed-in account and all of its server-side data,
  /// then drop back to a fresh guest. The privileged delete lives behind the
  /// Workers route `DELETE /api/account` (the Supabase client can't delete a
  /// user); it authenticates with the user's bearer token, and the server's
  /// service-role `admin.deleteUser` cascades every user-scoped table. On
  /// success we run the same teardown as sign-out — purge the per-user cache and
  /// clear the local session, which bootstraps a new anonymous guest. A failed
  /// request throws and leaves the session intact so the UI can surface it.
  func deleteAccount() async throws {
    let token = try await validAccessToken()
    var request = URLRequest(url: BackendConfig.apiBaseURL.appendingPathComponent("api/account"))
    request.httpMethod = "DELETE"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

    let (_, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
      throw DeleteAccountError.requestFailed((response as? HTTPURLResponse)?.statusCode ?? -1)
    }
    await clearSession(purgeUserData: true)
  }

  private func clearSession(purgeUserData: Bool) async {
    if purgeUserData {
      await onSignOutCleanup?()
    }
    // Local scope only: must not invalidate the user's web session. Clearing the
    // session emits `.signedOut`, which bootstraps a fresh guest session.
    try? await client.auth.signOut(scope: .local)
    userEmail = nil
  }
}
