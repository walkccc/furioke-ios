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

### Requirement: YouTube video-playback source

A `YouTubeAdapter` SHALL implement `MusicSource` as an **account-less, in-app
video-playback source** for the `.youtube` provider. It SHALL report
`requiresAccount = false`, `getAccount` SHALL return `nil`, and `connect` SHALL
resolve `.success` without any Google / YouTube login or deep link. Catalog
search SHALL go through the InnerTube-backed `youtube/search` Supabase Edge
Function (see the dedicated requirement); `resolveTracks` SHALL resolve
`(provider, videoId)` pairs through the same function. `playTrack` and `control`
SHALL drive an in-app YouTube IFrame Player (see the view-backed-source and
error-bridge requirements) and SHALL NOT return `MusicError.unsupported`. The
provider SHALL be framed in copy as a YouTube karaoke / video source, never as
"YouTube Music."

The adapter SHALL reuse the existing `MusicTrack` shape with
`providerTrackID = videoId`; no YouTube-specific track type is introduced.
`MusicProvider.youtube.playbackURI(forTrackID:)` SHALL return the YouTube
embed/watch form for a `videoId`.

The official YouTube **Data API SHALL NOT** be used for search in v1, and
InnerTube logic SHALL NOT live in the iOS binary.

#### Scenario: YouTube search returns provider-neutral tracks

- **WHEN** the user runs a Search query while the active provider is YouTube
- **THEN** the adapter calls the `youtube/search` Supabase Edge Function and
  returns provider-neutral `MusicTrack` values (`provider = .youtube`,
  `providerTrackID = videoId`) that the Search tab renders identically to
  Spotify or Apple Music results

#### Scenario: YouTube plays in-app

- **WHEN** the user taps a YouTube result
- **THEN** `playTrack` loads the `videoId` into the in-app YouTube IFrame Player
  and playback begins on the visible player surface; `control` does not return
  `MusicError.unsupported`

#### Scenario: Account-less selection

- **WHEN** the user selects YouTube as the active provider in Settings
- **THEN** no Google login, system prompt, or deep link occurs; `connect`
  resolves `.success` and `getConnection` reports `.connected(.youtube)`

#### Scenario: View-on-YouTube survives only as a failure fallback

- **WHEN** in-app playback fails hard for a track (e.g. region lock or embed
  disabled)
- **THEN** the UI MAY offer a "view on YouTube" hand-off as a fallback, but the
  default tap behavior is in-app playback, not the hand-off

### Requirement: YouTube IFrame playback error bridge

The `YouTubeAdapter` SHALL bridge the YouTube IFrame Player's JS `onError` event
through a `WKScriptMessageHandler` into a Swift handler and SHALL map JS error
codes to `MusicError`:

| YT error code | `MusicError`          |
| ------------- | --------------------- |
| 2             | `unplayable`          |
| 5             | `embedDisabled`       |
| 100           | `notFound`            |
| 101 / 150     | `regionLocked`        |
| (timeout 3s)  | `playbackDidNotStart` |

The mapped `MusicError` SHALL be surfaced on `MusicUpdate.playbackError`. On
failure the adapter SHALL clear its pending-track state so subsequent plays are
not blocked, and SHALL signal the `youtube/search` Edge Function to invalidate
the cache entry that produced a now-dead `videoId` (codes 100 / 101 / 150) so a
re-search resolves a live video. The BUFFERING-state snapshot SHALL return a
partial `MusicUpdate` carrying the pending track id and `isPlaying: false`
(instead of nil) so the now-playing surface renders a loading indicator rather
than freezing.

#### Scenario: JS error reaches Swift

- **WHEN** the IFrame Player emits `onError` with code 101
- **THEN** the bridge calls the Swift error handler, the adapter emits a
  `MusicUpdate` with `playbackError = .regionLocked`, and the UI surfaces a
  toast describing the region lock

#### Scenario: Dead videoId invalidates the search cache

- **WHEN** playback fails with code 100, 101, or 150 for a `videoId` that came
  from a cached `youtube/search` result
- **THEN** the adapter signals the Edge Function to invalidate that query's
  cache entry so the next identical search re-resolves a playable video

#### Scenario: Forever-buffering stall is detected

- **WHEN** `playTrack` is called for a video and 3 seconds elapse without a
  `.playing` state arriving from the IFrame
- **THEN** the adapter emits `playbackError = .playbackDidNotStart` and clears
  the pending `videoId` so the next play attempt is not blocked by stale state

### Requirement: View-backed music sources advertise a player surface

`MusicSource` SHALL advertise whether it requires a visible player surface via a
provider-neutral capability (e.g. `playerSurface: MusicPlayerSurface` defaulting
to `.none`). Spotify and Apple Music SHALL report `.none`; YouTube SHALL report
a video surface. `MusicState` SHALL remain headless and provider-neutral — it
SHALL NOT own or reference a `WKWebView`. The WKWebView + JS bridge SHALL live
in a dedicated controller (`YouTubePlayerController`) constructed at the
composition root and injected into the adapter (which drives playback) and the
player view (which displays it). Feature/view code SHALL decide whether to mount
a player surface by reading the active source's `playerSurface` capability, and
SHALL NOT branch on `provider == .youtube`.

#### Scenario: Headless sources need no surface

- **WHEN** the active source is Spotify or Apple Music
- **THEN** its `playerSurface` is `.none` and the NowPlaying surface renders the
  existing artwork backdrop with no embedded player

#### Scenario: Surface decided by capability, not vendor name

- **WHEN** the NowPlaying surface decides whether to mount a video player
- **THEN** it reads `activeSource.playerSurface`; it does not compare the
  provider against `.youtube`

#### Scenario: Surface torn down on provider switch

- **WHEN** the user switches away from a view-backed source
- **THEN** `teardownActive()` stops and releases the `YouTubePlayerController`'s
  WKWebView along with the adapter subscription, leaving no playing or hidden
  webview behind

### Requirement: YouTube search via Supabase Edge Function (InnerTube)

The iOS app SHALL obtain YouTube search and resolve results from a Supabase Edge
Function `youtube/search` that runs an unofficial InnerTube (ytmusicapi-style)
query against YouTube's internal API. The function SHALL return provider-neutral
results (`videoId`, `title`, `artists`, `durationMs`, `thumbnailURL`) and SHALL
cache `normalizedQuery → results`. The iOS app SHALL depend only on this
contract; the function's implementation lives in the separate backend/web repo
and MAY be hotfixed without an iOS App Store release. The iOS app SHALL NOT call
the official YouTube Data API for search and SHALL NOT embed InnerTube request
logic.

#### Scenario: Search hits the Edge Function, not the Data API

- **WHEN** the YouTube adapter searches the catalog
- **THEN** it issues a request to the `youtube/search` Supabase Edge Function
  and no request is made to `googleapis.com/youtube/v3/search`

#### Scenario: Edge Function unavailable degrades gracefully

- **WHEN** the Edge Function returns an error or is unreachable (e.g. an
  InnerTube breakage not yet hotfixed)
- **THEN** the adapter surfaces an empty result set with a "YouTube search is
  temporarily unavailable" state rather than crashing or hanging, and Spotify /
  Apple Music search remain unaffected

### Requirement: Adapter declares playback-rate capability

Each `MusicSource` adapter SHALL declare a boolean `supportsPlaybackRate`
capability flag, parallel to `supportsRepeat`. The flag indicates whether the
provider can change the active track's playback rate. Feature code SHALL read
this flag to decide whether to offer a speed control, and SHALL NOT assume any
provider supports rate changes. `MusicState` SHALL expose the active adapter's
flag (false when no provider is active).

#### Scenario: YouTube declares support

- **WHEN** the `YouTubeAdapter` is constructed
- **THEN** it reports `supportsPlaybackRate = true`

#### Scenario: Spotify and Apple Music decline

- **WHEN** the `SpotifyAdapter` or `MusicKitAdapter` is constructed
- **THEN** it reports `supportsPlaybackRate = false`, because neither SDK
  exposes a playback-rate control

### Requirement: setPlaybackRate control case

The `MusicControl` enum SHALL include a `setPlaybackRate(rate: Double)` case.
`MusicState.control` SHALL delegate it to the active adapter. An adapter that
reports `supportsPlaybackRate = false` SHALL return `.failure(.unsupported)` for
this case. An adapter that supports it SHALL apply the requested rate to its
player and return `.success(())`.

#### Scenario: Capable adapter applies the rate

- **WHEN** `control(.setPlaybackRate(rate: 0.5))` is dispatched to the YouTube
  adapter with a track loaded
- **THEN** the adapter sets the IFrame player's rate to 0.5× and returns
  `.success(())`

#### Scenario: Incapable adapter rejects the case

- **WHEN** `control(.setPlaybackRate(rate:))` is dispatched to the Spotify or
  Apple Music adapter
- **THEN** it returns `.failure(.unsupported)` and changes no playback state

### Requirement: MusicUpdate carries the live playback rate

The `MusicUpdate` value emitted by adapters SHALL include a `playbackRate`
`Double` reflecting the source's current rate. An adapter that does not support
rate changes SHALL emit `1.0`. Consumers SHALL treat `1.0` as normal speed.

#### Scenario: YouTube reports its rate

- **WHEN** the YouTube adapter is playing a track the user set to 0.75×
- **THEN** each `MusicUpdate` it emits carries `playbackRate == 0.75`

#### Scenario: Headless sources report normal speed

- **WHEN** the Spotify or Apple Music adapter emits an update
- **THEN** it carries `playbackRate == 1.0`

### Requirement: YouTube source resets rate on track load

Loading a new video into the YouTube source SHALL reset the playback rate to 1×,
so a fresh track never inherits the previous track's rate.

#### Scenario: New track starts at normal speed

- **WHEN** a video is playing at 0.5× and `playTrack` loads a different video
- **THEN** the new video plays at 1× and subsequent updates report
  `playbackRate == 1.0`
