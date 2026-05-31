## REMOVED Requirements

### Requirement: YouTube metadata-only client

**Reason**: Replaced by a real in-app YouTube video-playback source. The
metadata-only adapter was a placeholder that was never implemented, and its
"view on YouTube, no in-app playback" stance is the dead end this change removes.

**Migration**: None — no shipped behavior changes. YouTube gains in-app playback;
search/resolve move from the official Data API path to the InnerTube Edge
Function (see the added requirement).

### Requirement: YouTube IFrame error bridge (if hosted player ships in v1)

**Reason**: Superseded by the now-unconditional "YouTube IFrame playback error
bridge" requirement below — the hosted player ships in v1, so the conditional
framing no longer applies.

**Migration**: None.

## ADDED Requirements

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
