# guest-session Specification

## Purpose

Defines the Furioke iOS app's guest experience: a real but anonymous Supabase
session bootstrapped on cold start when no session is in the Keychain, so the
app is usable without signing in. It establishes the anonymous session as the
single source of truth for guest access, the core reading and playback flows a
guest can use, the reserved features (Translation, saved-song Library,
flashcards) gated behind an in-app sign-in prompt, the ephemerality of guest
sessions, and recovery when the anonymous bootstrap fails.

## Requirements

### Requirement: Automatic anonymous guest session on cold start

The app SHALL establish a real but anonymous Supabase session via
`signInAnonymously()` when it launches and no Supabase session is restored from
the Keychain, rather than presenting a sign-in wall. The resulting user SHALL be
a genuine `auth.users` row flagged `is_anonymous = true` with a real `user_id`,
persisted to the Keychain like any session. The app SHALL render the `AppShell`
for this guest exactly as it does for a permanent account. There SHALL NOT be a
parallel local flag governing guest access; the anonymous session is the single
source of truth.

#### Scenario: First launch lands in the app as a guest

- **WHEN** a user opens the app for the first time and no session exists in the
  Keychain
- **THEN** `signInAnonymously()` creates an `is_anonymous = true` session, the
  session is written to the Keychain, and the `AppShell` is shown with the
  Library tab selected — no sign-in wall is presented

#### Scenario: Guest session is restored across launches

- **WHEN** a guest force-quits and re-opens the app before the session ages out
- **THEN** the anonymous session is restored from the Keychain and the app lands
  directly in `AppShell` without creating a new anonymous user

### Requirement: Guest can use the core reading and playback experience

A guest (anonymous) session SHALL be able to browse and search the catalog,
connect and use every music provider (Spotify, Apple Music, YouTube), load
lyrics with on-device furigana, and use the reading-overrides / corrections
editor — exactly as a permanent account can. These flows authenticate with the
anonymous session's bearer token, which the backend's `withAuthedUser` read
routes accept.

#### Scenario: Guest reads lyrics with furigana

- **WHEN** a guest plays a track and the lyric fetch runs
- **THEN** `GET /api/lyrics` is called with the anonymous session's bearer
  token, succeeds, and the lyrics render with on-device furigana

#### Scenario: Guest connects a provider

- **WHEN** a guest taps a provider to connect in Settings
- **THEN** the provider OAuth/connect flow runs and, on success, the provider is
  usable under the guest's `user_id` just as for a permanent account

### Requirement: Reserved features require a permanent account

Translation, the saved-song Library, and flashcards SHALL be reserved for a
permanent (non-anonymous) account. When a guest invokes one of these actions the
app SHALL present an in-app sign-in prompt offering Sign in with Apple and Sign
in with Google, and SHALL NOT perform the reserved action until the guest
upgrades to a permanent account. The gate SHALL be a single shared seam so the
prompt copy and behavior are consistent across surfaces.

#### Scenario: Guest attempts a reserved action

- **WHEN** a guest enables Translation, taps Save-to-library, or triggers a
  flashcard save
- **THEN** the action does not run; instead the sign-in prompt is presented with
  Apple and Google options

#### Scenario: Reserved action proceeds after upgrade

- **WHEN** a guest completes sign-in from the prompt, upgrading to a permanent
  account
- **THEN** the previously blocked action becomes available and the user can
  perform it

### Requirement: Guest sessions are ephemeral

A guest session SHALL be understood as ephemeral: the shared Supabase project's
scheduled cleanup deletes anonymous users roughly 24 hours after creation,
cascading their provider tokens and related rows. The app SHALL NOT rely on a
guest session persisting indefinitely and SHALL bootstrap a fresh anonymous
session on a later launch when the prior one has been cleaned up. Because a
guest cannot persist a Library or flashcards, no durable user data is lost by
cleanup.

#### Scenario: A cleaned-up guest gets a fresh session

- **WHEN** a guest returns after their anonymous user has been cleaned up
  server-side and the stored refresh token is rejected
- **THEN** the app clears the dead session and bootstraps a new anonymous
  session, landing the user back in `AppShell`

### Requirement: Anonymous bootstrap failure is recoverable

The app SHALL NOT loop or wedge on a blank screen when `signInAnonymously()`
fails (anonymous sign-ins disabled in the Supabase project, CAPTCHA / rate
limiting, or the device is offline). Offline, it SHALL fall back to cached
content where available. Otherwise it SHALL surface a clear, retryable error
rather than silently leaving the user with no usable state.

#### Scenario: Bootstrap fails while online

- **WHEN** the app launches with no session and `signInAnonymously()` fails for
  a non-network reason
- **THEN** the app surfaces a clear, retryable message instead of a blank or
  spinning screen

#### Scenario: Bootstrap unavailable offline

- **WHEN** the app launches with no session while offline
- **THEN** the app presents cached content where available and retries the
  anonymous bootstrap when connectivity returns
