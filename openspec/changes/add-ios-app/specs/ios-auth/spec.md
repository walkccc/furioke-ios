## ADDED Requirements

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

Signing out from the Settings tab SHALL delete the Supabase session from the
Keychain, clear in-memory session state, purge per-user SwiftData entities (see
[[ios-offline-cache]]), and transition the app to the sign-in surface. Provider
connections (Spotify access token, MusicKit authorization) SHALL also be revoked
locally so a different signed-in user on the same device does not inherit them.

#### Scenario: Sign-out is end-to-end

- **WHEN** the user taps **Sign out** in Settings and confirms
- **THEN** the Keychain Supabase entry is deleted, all SwiftData entities scoped
  to that user are purged, the local Spotify access token is cleared, the local
  MusicKit authorization is forgotten, and the app shows the sign-in surface

#### Scenario: Sign-in by a different user starts clean

- **WHEN** user A signs out and user B signs in on the same device
- **THEN** user B's Library, overrides, and translation cache reflect only their
  server-side state, with no inherited entries from user A

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
