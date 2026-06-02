## Purpose

Defines iOS authentication against the shared Supabase project: Google OAuth
presented through `ASWebAuthenticationSession`, session tokens persisted in the
iOS Keychain and restored across launches, transparent refresh-on-expiry via
`supabase-swift`, and sign-out that clears local state and revokes provider
connections. The iOS session is independent of any browser session for the same
Supabase user.

## Requirements

### Requirement: Sign-in via Supabase Google OAuth using ASWebAuthenticationSession

The app SHALL authenticate users against the same Supabase project the web app
uses, via the Google OAuth provider, by presenting Supabase's hosted sign-in URL
inside `ASWebAuthenticationSession`. The redirect callback SHALL use the custom
URL scheme `furioke://auth/callback`, registered as the app's URL type. On
callback, the app SHALL extract the Supabase session tokens and persist them to
the iOS Keychain.

#### Scenario: First sign-in flow

- **WHEN** a signed-out user taps **Sign in with Google** on the sign-in surface
- **THEN** `ASWebAuthenticationSession` opens Supabase's Google OAuth URL, the
  user completes Google sign-in, the system redirects to
  `furioke://auth/callback`, the app extracts the access + refresh tokens and
  writes them to the Keychain

#### Scenario: User cancels the sign-in sheet

- **WHEN** the user dismisses the `ASWebAuthenticationSession` sheet without
  completing sign-in
- **THEN** the app remains on the sign-in surface, no tokens are stored, and no
  error toast is shown

### Requirement: Native Sign in with Apple via id-token

The app SHALL offer Sign in with Apple using the native flow — an
`ASAuthorizationController` request from `ASAuthorizationAppleIDProvider`,
presented from a native Apple sign-in button — rather than a web redirect. The
app SHALL generate a cryptographically random nonce, send its SHA-256 hash in
the Apple authorization request, and exchange the returned identity token
together with the raw nonce via `supabase-swift`
`signInWithIdToken(credentials: .init(provider: .apple, idToken:, nonce:))`. The
target SHALL declare the **Sign in with Apple** capability/entitlement. The
existing Google OAuth flow SHALL remain available alongside it. User
cancellation SHALL be silent (no error surfaced); genuine failures SHALL surface
inline.

#### Scenario: Apple sign-in completes

- **WHEN** a user taps **Sign in with Apple** and authorizes with Face ID /
  Touch ID
- **THEN** the app receives the Apple identity token, exchanges it with the raw
  nonce via `signInWithIdToken`, and a permanent Supabase session is established
  and written to the Keychain

#### Scenario: Nonce is hashed to Apple, raw to Supabase

- **WHEN** the app builds the Apple authorization request
- **THEN** the request carries the SHA-256 hash of the nonce, and the subsequent
  `signInWithIdToken` call carries the raw (unhashed) nonce

#### Scenario: User cancels the Apple sheet

- **WHEN** the user dismisses the Apple authorization sheet without completing
  it
- **THEN** no session changes, no tokens are stored, and no error is surfaced

### Requirement: Anonymous-session bootstrap when no session exists

The app SHALL establish an anonymous Supabase session via `signInAnonymously()`
on cold start whenever the initial-session restore reports no Keychain session,
instead of remaining signed-out. `AuthService` SHALL expose whether the current
session is anonymous (`is_anonymous`) so feature surfaces can distinguish a
guest from a permanent account. The session lifecycle (Keychain persistence,
refresh-on-expiry, observation) SHALL apply to anonymous sessions identically to
permanent ones.

#### Scenario: No session bootstraps a guest

- **WHEN** the initial session restore finds no Keychain session
- **THEN** `AuthService` calls `signInAnonymously()`, applies the resulting
  anonymous session, and reports the session as anonymous

#### Scenario: Anonymous flag is exposed

- **WHEN** a guest session is active
- **THEN** `AuthService` reports `is_anonymous == true`; when a permanent
  account is active it reports `false`

### Requirement: Upgrade a guest session in place via linkIdentity

The app SHALL, when the current session is anonymous and the user signs in with
Apple or Google, attempt to link the new identity to the existing anonymous user
so the `user_id` — and any music-provider tokens connected under it — survive
the upgrade, rather than creating a fresh user. If linking cannot proceed (the
identity already belongs to another account, or manual linking is disabled), the
app SHALL fall through to a normal sign-in to that account; the orphaned
anonymous session ages out via server-side cleanup.

#### Scenario: Guest upgrades and keeps their provider connection

- **WHEN** a guest who has connected Spotify signs in with Apple or Google
- **THEN** the identity is linked to the existing anonymous `user_id`, the
  session becomes a permanent account, and the previously connected Spotify
  tokens remain associated with that same `user_id`

#### Scenario: Link conflict falls through to plain sign-in

- **WHEN** a guest signs in with an identity that already belongs to another
  account
- **THEN** the link attempt fails, the app signs in to that existing account
  instead, and the orphaned anonymous session is left to age out

### Requirement: JWT stored in Keychain, persisted across launches

The app SHALL store the Supabase access token, refresh token, and expiry in the
iOS Keychain under a service identifier dedicated to Furioke. The Keychain item
SHALL NOT be marked accessible when the device is locked
(`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`). On every cold start, the
app SHALL read the session from the Keychain before deciding which root surface
to render (sign-in vs. tab bar).

#### Scenario: Session survives app restart

- **WHEN** a signed-in user force-quits the app and re-opens it
- **THEN** the app reads the session from the Keychain and lands directly on the
  Library tab without re-authenticating

#### Scenario: Tokens are not accessible while device is locked at boot

- **WHEN** the device is freshly booted and still locked
- **THEN** the Keychain item is not readable; the app waits for first unlock
  before attempting to restore the session

### Requirement: Refresh-on-expiry via supabase-swift

The app SHALL use `supabase-swift` to manage session refresh. When the access
token is within 60 seconds of expiry or has expired, the next authenticated
request SHALL trigger a refresh using the stored refresh token. A successful
refresh SHALL update the Keychain. A failed refresh (refresh token invalidated
by Supabase) SHALL clear the Keychain and transition the app to the sign-in
surface.

#### Scenario: Access token refreshed transparently

- **WHEN** the app issues a backend request after the access token has expired
  but the refresh token is still valid
- **THEN** `supabase-swift` refreshes the session, the new access token is used
  for the request, and the Keychain is updated

#### Scenario: Invalid refresh token signs out

- **WHEN** the refresh call returns an `invalid_grant` or equivalent error
- **THEN** the Keychain entry is cleared, the local session state is reset, and
  the app transitions to the sign-in surface within one navigation tick

### Requirement: Sign-out clears Keychain and purges per-user cache

Signing out from the Settings tab SHALL delete the permanent Supabase session
from the Keychain, clear in-memory session state, purge per-user SwiftData
entities, and revoke local provider connections (Spotify access token, MusicKit
authorization) so a different user on the same device does not inherit them.
After sign-out the app SHALL return to a guest experience by bootstrapping a new
anonymous session — it SHALL NOT present a full-screen sign-in wall. The
per-user cache purge SHALL complete before the new anonymous session is
established so the guest does not inherit the prior user's cached data.

#### Scenario: Sign-out drops to a guest session

- **WHEN** the user taps **Sign out** in Settings and confirms
- **THEN** the Keychain permanent-session entry is deleted, all SwiftData
  entities scoped to that user are purged, the local Spotify access token is
  cleared, the local MusicKit authorization is forgotten, and the app bootstraps
  a fresh anonymous session and remains in `AppShell` as a guest

#### Scenario: Sign-in by a different user starts clean

- **WHEN** user A signs out and user B signs in on the same device
- **THEN** user B's Library, overrides, and translation cache reflect only their
  server-side state, with no inherited entries from user A or the interim guest
  session

### Requirement: Signed-in user identity exposed for display

`AuthService` SHALL expose the signed-in user's email as a read-only, observable
property for display by feature surfaces. It SHALL capture the email from the
Supabase session whenever the session is applied (initial session, sign-in,
token refresh, user update) and SHALL clear it on sign-out or when no session is
present. The property SHALL be derived from the in-memory session only — reading
it SHALL NOT trigger a network request. This is a display-only accessor; it
SHALL NOT alter the existing `State` cases or the session-lifecycle behavior.

#### Scenario: Email available while signed in

- **WHEN** a user signs in (or a session is restored on cold start) with email
  `jay@example.com`
- **THEN** `AuthService` exposes `jay@example.com` as the signed-in user's email
  without performing any network fetch

#### Scenario: Email cleared on sign-out

- **WHEN** the user signs out
- **THEN** `AuthService` clears the exposed email so no stale identity remains

### Requirement: Independent of the web session in v1

The iOS app's session SHALL be independent of any browser session for the same
Supabase user. Signing in on the iOS app SHALL NOT affect any browser session,
and signing out of the iOS app SHALL NOT sign the user out of the web app.
Cross-device session sharing is explicitly deferred.

#### Scenario: Sign-out is per-device

- **WHEN** a user is signed in on both web (Safari on macOS) and the iOS app,
  and signs out from the iOS app
- **THEN** the macOS Safari session remains valid; the user remains signed in on
  web until they sign out there separately
