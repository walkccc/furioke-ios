## ADDED Requirements

### Requirement: Search across the active connected provider

The Search tab SHALL run catalog search against the active connected provider's
adapter (`[[ios-music-source]]`). Results SHALL be returned in the
provider-neutral track shape so the rendering is identical across providers and
SHALL render via the shared `RowItem` primitive (see [[ios-design-system]]). The
user SHALL NOT be able to search a provider they have not connected. The search
field SHALL wear `Materials.chromeGlass` at the top of the Search tab.

#### Scenario: Searching Spotify catalog

- **WHEN** the active provider is Spotify (connected) and the user types `lemon`
  into the search field
- **THEN** the adapter calls Spotify's search directly against `api.spotify.com`
  using the SDK's current access token (no `/api/spotify/search` round trip on
  iOS), results render via `RowItem` (title, artist, album, duration), and the
  active-provider indicator shows Spotify

#### Scenario: Searching MusicKit catalog

- **WHEN** the active provider is MusicKit (authorized) and the user types a
  query
- **THEN** the adapter calls MusicKit's catalog search via
  `MusicCatalogSearchRequest`, returns provider-neutral rows, and renders them
  identically to Spotify results

#### Scenario: Searching YouTube catalog

- **WHEN** the active provider is YouTube and the user types a query
- **THEN** the adapter calls `/api/youtube/search`, returns provider-neutral
  rows, and labels each as metadata-only (no in-app playback)

#### Scenario: No provider connected

- **WHEN** the user opens the Search tab with no provider connected
- **THEN** the surface shows an `EmptyState` directing the user to Settings to
  connect a provider; the search field is disabled

### Requirement: Tap result to play (no tab switch)

The Search tab SHALL invoke `NowPlayingState.play(track:)` when the user taps a
search result for a playback-capable provider (Spotify, MusicKit). The play
entry point SHALL request expansion of the persistent mini-player into
`NowPlayingSheet` via `MiniPlayerExpansion.requestExpand()` rather than
switching the active tab. Tapping a YouTube result SHALL present a "view on
YouTube" affordance instead of attempting in-app playback.

#### Scenario: Tap-to-play on Spotify or MusicKit

- **WHEN** the user taps a result while the active provider is Spotify or
  MusicKit
- **THEN** `NowPlayingState.play(track:)` is invoked, the persistent mini-player
  expands into `NowPlayingSheet` via the shared matched- geometry namespace, and
  the Search tab remains the active tab

#### Scenario: Tap a YouTube result

- **WHEN** the user taps a YouTube result
- **THEN** the app opens the YouTube app or web URL for the result; the
  mini-player is not expanded; the active tab does not change

### Requirement: Save-to-library from search results

Each search result row SHALL present a Save affordance that inserts the track
into the user's `songs` table via the same save flow used by `[[song-library]]`.
The affordance SHALL show a "Saved" state when the track is already in the
user's library.

#### Scenario: Save from a result

- **WHEN** the user taps the Save affordance on a search result
- **THEN** a row is inserted into `songs` carrying the
  `(provider, provider_track_id)` tuple, title, artist, album, and duration; the
  Library tab reflects the new song

#### Scenario: Save state for already-saved tracks

- **WHEN** a result corresponds to a track the user has already saved
- **THEN** the row's Save affordance shows a "Saved" state instead of the
  default Save action

### Requirement: Search input is debounced

The search field SHALL debounce input by approximately 300 ms before issuing an
adapter search, so a typing user does not produce a request per keystroke. Empty
input SHALL clear the result list immediately.

#### Scenario: Debounce groups keystrokes into one request

- **WHEN** the user types a 6-character query without pausing
- **THEN** at most one search request is issued after the user stops typing for
  ~300 ms

#### Scenario: Clearing the field clears results

- **WHEN** the user clears the search field
- **THEN** the result list empties immediately, with no pending or in-flight
  request continuing to populate it
