## Purpose

The Search capability runs catalog search against the active connected provider
and returns results in a provider-neutral shape so rendering is identical
regardless of which provider is active. Users can tap a result to play it
without leaving the Search tab, and save any result into their library directly
from the results list. Input is debounced so a typing user does not generate a
request per keystroke.

## Requirements

### Requirement: Search across the active connected provider

The Search tab SHALL run catalog search against the active connected provider's
adapter. Results SHALL be returned in the provider-neutral track shape so the
rendering is identical across providers and SHALL render via the shared
`RowItem` primitive. The user SHALL NOT be able to search a provider they have
not connected. The Search tab SHALL present a rounded `Typography.pageTitle`
header at the top of the content, with the search field directly below it. The
search field SHALL be a custom in-content field (not a navigation-bar
`.searchable` field) wearing `Materials.chromeGlass`, and SHALL be disabled
until a provider is connected.

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

#### Scenario: Rounded title aligns with the other tabs

- **WHEN** the Search tab is displayed
- **THEN** the rounded "Search" title sits at the top of the content (the same
  top offset as the Library and Settings hero titles), with the glass search
  field directly beneath it

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
into the user's `songs` table via the same save flow. The affordance SHALL show
a "Saved" state when the track is already in the user's library.

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

### Requirement: Recent search history

The Search tab SHALL keep a recent-search history persisted across launches. A
search term SHALL be recorded when the user submits the field and when the user
plays a result. The history SHALL be trimmed of surrounding whitespace,
de-duplicated case-insensitively, ordered newest-first, and capped at a small
fixed number of entries. The history SHALL be local to the device. When the
Search tab is idle (connected, with an empty query) and the history is
non-empty, the tab SHALL surface the history as a list whose rows re-run a term
when tapped; the user SHALL be able to remove a single term and to clear the
whole history. When the history is empty, the idle state SHALL show the search
empty-state instead.

#### Scenario: A played result records its search term

- **WHEN** the user searches `lemon` and taps a result to play it
- **THEN** `lemon` is stored as the most-recent search term and persists across
  app launches

#### Scenario: Submitting records the term

- **WHEN** the user types a query and submits the search field
- **THEN** the trimmed query is stored as the most-recent search term

#### Scenario: Recent terms are de-duplicated newest-first

- **WHEN** the user searches a term that already exists in the history
- **THEN** it moves to the top of the list rather than being duplicated, and the
  list stays within its fixed cap

#### Scenario: Idle state surfaces history

- **WHEN** the user opens the Search tab with a provider connected, an empty
  query, and a non-empty history
- **THEN** the recent terms are listed; tapping a term re-runs the search for it

#### Scenario: Removing and clearing history

- **WHEN** the user swipes a recent term to remove it, or taps Clear
- **THEN** that term (or the entire history) is removed and the change persists

#### Scenario: Empty history falls back to the empty-state

- **WHEN** the Search tab is idle and the history is empty
- **THEN** the search `EmptyState` is shown instead of the recent-search list
