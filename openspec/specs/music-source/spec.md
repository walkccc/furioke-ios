## Purpose

This capability defines a provider-neutral Swift `MusicSource` adapter contract
that feature code depends on instead of vendor SDK types, along with a shared
`MusicError` failure vocabulary and a `MusicUpdate` snapshot that carries an
optional mid-session playback error. Concrete adapters implement this contract:
a fully client-side Spotify iOS SDK adapter (token held and renewed on-device,
Web API called directly), a MusicKit adapter using Apple-native authorization
and in-app playback, and a metadata-only YouTube client that resolves and
searches tracks without in-app playback. The user selects exactly one active
provider at a time, persisted on device and restored on launch.

## Requirements

### Requirement: Swift `MusicSource` adapter contract

The iOS app SHALL define a Swift `MusicSource` protocol mirroring the shape of
the web app's adapter contract. The protocol SHALL expose: `provider` id,
`requiresAccount`, `supportsRepeat`, `getConnection`, optional `getAccount`, an
`updates` async stream of playback snapshots, `connect`, `disconnect`,
`control`, `playTrack`, and `resolveTracks`. Feature code (NowPlaying, Library,
Search) SHALL depend only on this protocol, never on `SPTAppRemote`, `MusicKit`,
or YouTube HTTP types directly.

#### Scenario: A feature reads playback state

- **WHEN** a feature needs the currently-playing track, playback position, or
  connection state
- **THEN** it reads them from a `@MainActor` observable (`MusicState`) that
  sources from the active `MusicSource` adapter, not from a provider-specific
  SDK type

#### Scenario: A feature issues transport control

- **WHEN** a feature needs to play, pause, skip, seek, or loop
- **THEN** it calls the music observable's `control` function, which delegates
  to the active adapter's `control` and returns a provider-neutral
  `Result<Void, MusicError>`

### Requirement: `MusicError` vocabulary

The app SHALL expose a `MusicError` enum carrying the distinct failure reasons
surfaced by the adapter layer. The enum SHALL include at least: `notInstalled`,
`userCancelled`, `handshakeTimeout`, `transportError`, `renewFailed`,
`cancelled`, `needsReconnect`, `providerRejected(String)`, `unsupported`,
`unplayable`, `embedDisabled`, `notFound`, `regionLocked`,
`playbackDidNotStart`. Feature code SHALL map each reason to its distinct user
message; the catch-all "isn't running on this device" copy from the earlier iOS
implementation SHALL NOT be reintroduced.

#### Scenario: Connect failure carries a specific reason

- **WHEN** a connect attempt fails
- **THEN** the resulting `MusicError` carries one of `notInstalled`,
  `userCancelled`, `handshakeTimeout`, `transportError`, `renewFailed`, or
  `cancelled` — never a generic catch-all reason

#### Scenario: User cancellation is silent

- **WHEN** the user backs out of the Spotify auth screen before completing
- **THEN** the adapter resolves with `MusicError.userCancelled` and the UI shows
  no toast or banner

### Requirement: `MusicUpdate` carries optional playback error

The `MusicUpdate` value emitted by adapters SHALL include an optional
`playbackError: MusicError?` field so mid-session failures (e.g., a YouTube
region-lock that fires after `playTrack` succeeded) surface to the UI.
`MusicState` SHALL expose a `lastPlaybackError` derived from adapter emissions
for feature views to render toasts against.

#### Scenario: Mid-session failure surfaces to UI

- **WHEN** the adapter emits a `MusicUpdate` carrying a non-nil `playbackError`
- **THEN** `MusicState.lastPlaybackError` updates and the NowPlaying surface
  presents a toast describing the failure

### Requirement: Spotify iOS SDK adapter — fully client-side

A `SpotifyAdapter` SHALL implement `MusicSource` using Spotify's iOS SDK
(`SPTSessionManager` + `SPTAppRemote`). The Spotify iOS SDK SHALL hold the
access token on-device and SHALL auto-renew via
`SPTSessionManager.renewSession()`. The adapter SHALL NOT call
`/api/spotify/sdk-token`, and SHALL NOT create or update a `provider_tokens` row
for iOS-only users. The web app's server-mediated Spotify auth remains unchanged
for the web client.

Spotify Web API calls from iOS (catalog search, device list, device transfer,
`resolveTracks`) SHALL issue directly against `api.spotify.com` using the SDK's
current access token as Bearer auth. The adapter SHALL NOT route these through
Furioke server proxies (`/api/spotify/devices`, `/api/spotify/control`,
`/api/spotify/tracks`, `/api/spotify/search`); the web client continues to use
those routes.

The adapter SHALL publish `MusicUpdate` snapshots via its `updates` stream
whenever `SPTAppRemote` emits `playerStateDidChange`, exposing
`playbackMode = "native-sdk"`.

#### Scenario: No server token round trip on connect

- **WHEN** a user connects Spotify in the iOS app
- **THEN** the deep-link to Spotify completes, `SPTSessionManager` returns a
  session containing the access token, the adapter passes that token to
  `SPTAppRemote`, and no call is made to `/api/spotify/sdk-token` or any other
  Furioke server route for token brokering

#### Scenario: Direct Spotify Web API calls

- **WHEN** the iOS app needs to list devices, transfer playback, or resolve
  track metadata
- **THEN** the adapter calls `api.spotify.com` directly using the SDK's current
  access token; no Furioke server proxy is in the loop

#### Scenario: Native event-driven playback

- **WHEN** Spotify reports a playback state change
- **THEN** the adapter publishes a `MusicUpdate` snapshot within one run-loop
  tick, carrying `playbackMode = "native-sdk"` and the new position, without any
  poll-based fallback

#### Scenario: 401 triggers SDK renewal

- **WHEN** a direct `api.spotify.com` call returns 401
- **THEN** the adapter calls `SPTSessionManager.renewSession()`, retries the
  failing call once, and on second failure attempts a silent `initiateSession()`
  re-issue before surfacing `renewFailed`

#### Scenario: Independent of web session

- **WHEN** a user connects Spotify on the web app and later opens the iOS app
- **THEN** the iOS app does not inherit the web session; the user completes the
  iOS deep-link flow once (one tap if still authorized in the Spotify app,
  otherwise a full reconnect)

### Requirement: Spotify connect state machine

The Spotify connect path SHALL be driven by an explicit state machine with
phases `idle → linking → connected | failed(reason)`. The state machine SHALL be
the only path that resolves the connect operation, preventing double-resume and
never-resume. The adapter SHALL NOT use `withCheckedContinuation` for the
connect handshake.

#### Scenario: Double delegate callback does not crash

- **WHEN** the Spotify SDK delegate fires the connection-established callback
  twice for the same connect attempt (a known race)
- **THEN** the state machine accepts only the first event for the
  `linking → connected` transition; subsequent events are ignored without
  resuming a continuation a second time

#### Scenario: Delegate-never-fires surfaces a timeout

- **WHEN** the Spotify SDK delegate does not fire any callback within 8 seconds
  of `connect()`
- **THEN** the state machine transitions to `failed(handshakeTimeout)` so the UI
  does not stick on "Checking…"

### Requirement: Spotify foreground grace window

After UIScene transitions back to `.active`, the Spotify adapter SHALL ignore
the first `ECONNREFUSED` from the SDK transport for 1500 ms. The adapter SHALL
silently re-issue `appRemote.connect()` once before surfacing a transport
failure. Outside the grace window, two consecutive `ECONNREFUSED` results SHALL
surface
`MusicError.transportError("Couldn't connect to Spotify. Open the Spotify app and try again.")`.

#### Scenario: First ECONNREFUSED inside grace window is absorbed

- **WHEN** Furioke resumes from background after the Spotify-app handoff and the
  SDK transport emits `ECONNREFUSED` within 1500 ms
- **THEN** the adapter ignores the error, retries the connect once, and surfaces
  success if the retry resolves cleanly

#### Scenario: Genuinely missing Spotify app surfaces notInstalled

- **WHEN** the user has uninstalled the Spotify app and attempts to connect
- **THEN** `UIApplication.canOpenURL("spotify://") == false` short- circuits to
  `MusicError.notInstalled` before the SDK transport is touched, so the grace
  window does not mask the genuine "not installed" case

### Requirement: MusicKit adapter using Apple-native authorization

A `MusicKitAdapter` SHALL implement `MusicSource` using Apple's `MusicKit` Swift
framework. The adapter SHALL obtain authorization via
`MusicAuthorization.request()` and SHALL NOT call `/api/apple-music/token` (the
server-signed JWT route is web-only; native MusicKit handles its own developer
token internally on iOS). The adapter SHALL play in-app via
`ApplicationMusicPlayer.shared` and SHALL search the catalog via
`MusicCatalogSearchRequest`.

#### Scenario: Native authorization, no server JWT

- **WHEN** a user connects Apple Music in the iOS app
- **THEN** the app calls `MusicAuthorization.request()` and the user is prompted
  by the system; no call to `/api/apple-music/token` is made

#### Scenario: Music state updates via MusicKit events

- **WHEN** the user starts or skips a track in Apple Music (in the Furioke app
  or elsewhere)
- **THEN** the MusicKit adapter publishes a `MusicUpdate` reflecting the new
  track and position

#### Scenario: No subscription surfaces a useful message

- **WHEN** the user attempts to connect Apple Music without an active
  subscription
- **THEN** the resulting `MusicError` carries a message that explains the
  subscription requirement rather than a generic failure

### Requirement: YouTube metadata-only client

A `YouTubeMetadataAdapter` SHALL implement only the metadata surface of the
`MusicSource` protocol: `resolveTracks` (via `/api/youtube/videos`) and catalog
search (via `/api/youtube/search`). The adapter's `getConnection` SHALL report
`requiresAccount = false`, its `updates` stream SHALL not emit playback
snapshots, and its `control` and `playTrack` calls SHALL return
`MusicError.unsupported`. The UI SHALL present a "view on YouTube" affordance
for YouTube tracks instead of attempting in-app playback.

#### Scenario: YouTube search returns provider-neutral tracks

- **WHEN** the user runs a Search query while the active provider is YouTube
- **THEN** the adapter calls `/api/youtube/search` and returns provider- neutral
  track shapes that the Search tab renders identically to Spotify or Apple Music
  results

#### Scenario: YouTube playback is not supported in-app

- **WHEN** a user taps a YouTube result intending to play
- **THEN** the UI presents a "view on YouTube" affordance (opens the YouTube app
  or web) and the adapter does not attempt to control in-app playback

### Requirement: YouTube IFrame error bridge (if hosted player ships in v1)

If an in-app YouTube IFrame player ships in v1, the adapter SHALL bridge the JS
`onError` event through a `WKScriptMessageHandler` into a Swift handler. The
adapter SHALL map JS error codes to `MusicError`:

| YT error code | `MusicError`          |
| ------------- | --------------------- |
| 2             | `unplayable`          |
| 5             | `embedDisabled`       |
| 100           | `notFound`            |
| 101 / 150     | `regionLocked`        |
| (timeout 3s)  | `playbackDidNotStart` |

The mapped `MusicError` SHALL be surfaced on `MusicUpdate.playbackError`. On
failure, the adapter SHALL clear its pending-track state so subsequent plays are
not blocked. The BUFFERING-state `snapshot()` SHALL return a partial
`MusicUpdate` carrying the pending track id and `isPlaying: false` instead of
nil so the now-playing surface renders a loading indicator instead of freezing.

#### Scenario: JS error reaches Swift

- **WHEN** the IFrame Player emits `onError` with code 101
- **THEN** the bridge calls the Swift error handler, the adapter emits a
  `MusicUpdate` with `playbackError = .regionLocked`, and the UI surfaces a
  toast describing the region lock

#### Scenario: Forever-buffering stall is detected

- **WHEN** `playTrack` is called for a video and 3 seconds elapse without a
  `.playing` state arriving from the IFrame
- **THEN** the adapter emits `playbackError = .playbackDidNotStart` and clears
  `currentVideoId` so the next play attempt is not blocked by stale state

### Requirement: Single-active-provider selection persisted on device

The user SHALL select exactly one active music provider at a time. Selection
SHALL persist in `UserDefaults` under a dedicated key. On launch, the app SHALL
restore the previously-active provider and SHALL NOT auto-connect a different
provider in the background.

#### Scenario: Active provider survives launches

- **WHEN** the user selects **Apple Music** and force-quits the app
- **THEN** on next launch the Apple Music adapter is the active source and the
  UI's provider indicator shows Apple Music

#### Scenario: Provider switch tears down the previous adapter

- **WHEN** the user switches the active provider in Settings
- **THEN** the previous adapter's subscriptions are torn down exactly once (no
  leaked update streams) before the new adapter activates

#### Scenario: Disconnecting clears active provider

- **WHEN** the user disconnects the currently active provider in Settings
- **THEN** no provider is active, the NowPlaying surface shows a "connect a
  provider" empty state, and `UserDefaults` reflects no active provider until
  the user picks one
