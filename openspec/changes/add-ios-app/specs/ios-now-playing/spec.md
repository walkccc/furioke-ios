## ADDED Requirements

### Requirement: NowPlaying is delivered as the expanded mini-player

NowPlaying SHALL be delivered as `NowPlayingSheet`, the expanded state of the
persistent `MiniPlayer` owned by `AppShell` (see [[ios-app-shell]]). NowPlaying
SHALL NOT be a peer tab destination. The mini-player and the sheet SHALL share a
`matchedGeometryEffect` namespace owned by `AppShell` so the artwork, title, and
artist morph in place between collapsed and expanded states rather than
cross-fading.

#### Scenario: AppShell owns the matched-geometry namespace

- **WHEN** the mini-player and `NowPlayingSheet` morph artwork / title / artist
  between collapsed and expanded states
- **THEN** they share a single `@Namespace` declared on `AppShell`; neither the
  mini-player nor the sheet creates its own namespace

#### Scenario: Reduced-motion falls back to cross-fade

- **WHEN** the user has `accessibilityReduceMotion` enabled
- **THEN** the matched-geometry transition automatically degrades to a
  cross-fade and the sheet's spring transition uses the system-reduced duration

### Requirement: NowPlaying is the primary in-app player

NowPlayingSheet SHALL act as the user's primary playback surface, driving the
active music provider directly when the user starts a track from within the
Furioke app. A single `NowPlayingState.play(track:)` entry point SHALL be the
seam from Library / Search into playback: it SHALL call `MusicSource.playTrack`
on the active adapter, set `MusicState.source = .userInitiated(track)`, start
the lyric load against that track without waiting for the adapter's
`playerStateDidChange` echo, AND call `MiniPlayerExpansion.requestExpand()`.
Library and Search SHALL NOT switch tabs to "go to NowPlaying" — they request
expansion of the persistent mini-player.

#### Scenario: Library tap starts playback and expands the sheet

- **WHEN** the user taps a song row in the Library tab
- **THEN** the app calls `NowPlayingState.play(track:)`, which calls the active
  adapter's `playTrack`, requests expansion of the persistent mini-player into
  `NowPlayingSheet` via the shared matched-geometry namespace, and begins
  fetching lyrics for that track immediately — the lyric fetch does not wait for
  the SDK to echo the new track back, and the active tab does not change

#### Scenario: Search tap starts playback and expands the sheet

- **WHEN** the user taps a result row from the Search tab while the active
  provider supports playback (Spotify, MusicKit)
- **THEN** the app calls `NowPlayingState.play(track:)`, requests expansion into
  `NowPlayingSheet`, and the lyric load uses the Search result's metadata

#### Scenario: User-initiated playback is labelled

- **WHEN** NowPlayingSheet is showing a `.userInitiated` source
- **THEN** the UI renders a `GlassCapsule` "Playing on {provider}" chip (no
  companion-mode indicator) and the transport controls reflect the active
  adapter's capabilities

### Requirement: Transport controls via the shared TransportButton primitive

NowPlayingSheet SHALL present in-app transport controls — play, pause, previous,
next — using the shared `TransportButton` primitive (see [[ios-design-system]]).
Each button SHALL delegate to the active adapter's `control` function. Controls
that the active adapter or the current playback context cannot service SHALL be
visually disabled (rendered at ~35% opacity) rather than hidden, so the layout
is stable. Each tap SHALL animate via `Motion.pop` with the `.bounce`
SymbolEffect choreography.

#### Scenario: Play / pause delegate to the adapter

- **WHEN** the user taps play or pause in NowPlayingSheet while a track is
  loaded
- **THEN** the corresponding `control(.play)` or `control(.pause)` is invoked on
  the active adapter and the player's visual state updates from the adapter's
  resulting emission

#### Scenario: Previous / next route through the adapter's queue

- **WHEN** the user taps previous or next
- **THEN** the active adapter's `control(.prev)` or `control(.next)` is invoked,
  the adapter advances its queue, and the new track's lyrics load via the
  companion path (since the adapter, not Furioke, chose the next track)

#### Scenario: Unsupported control is disabled, not hidden

- **WHEN** the active adapter reports that previous is not available (e.g., on
  YouTube which has no queue)
- **THEN** the previous button renders disabled in the same position; the next,
  play, and pause buttons remain untouched

### Requirement: Draggable position scrubber with haptic detents

NowPlayingSheet SHALL present a draggable position scrubber via the shared
`Scrubber` primitive, bound to the active adapter's playback- position
emissions. While the user drags, the scrubber SHALL show a local preview value
and SHALL NOT route position updates from the adapter into the scrubber. On
release, the app SHALL call `control(.seek(positionMs))` and SHALL suppress
incoming position emissions for a short settling window to avoid snap-back. The
scrubber SHALL fire a `.light` haptic impact when the drag crosses the 25 / 50 /
75% detents. The scrubber SHALL be disabled when the active provider does not
support seek (YouTube metadata-only).

#### Scenario: Drag previews, release seeks

- **WHEN** the user drags the scrubber from 30s to 90s and releases
- **THEN** during the drag the scrubber displays 90s without affecting playback;
  on release the adapter's `control(.seek(90_000))` is invoked and playback
  moves to that point

#### Scenario: Haptic detents at quarter points

- **WHEN** the user drags the scrubber across the 25%, 50%, or 75% detent
- **THEN** a `.light` impact fires exactly once per detent crossing during the
  drag

#### Scenario: Position emissions ignored during drag

- **WHEN** an adapter `positionMs` emission arrives while the user is actively
  dragging the scrubber
- **THEN** the scrubber does not move; the latest emission is dropped until the
  drag ends

#### Scenario: Scrubber disabled on metadata-only providers

- **WHEN** the active provider is YouTube
- **THEN** the scrubber is rendered disabled and shows the playback position
  only if any is reported (else 0)

### Requirement: Queue / up-next surface

NowPlayingSheet SHALL present a queue / up-next surface listing the next tracks
the active provider will play. The surface SHALL source its entries from the
active adapter's queue state (Spotify SDK `getPlayerState().track` plus its
queue projection; MusicKit `SystemMusicPlayer.queue.entries`). Where the
provider supports queue manipulation, the user SHALL be able to tap an entry to
jump to it and SHALL be able to remove an entry. When the active provider does
not expose queue state (YouTube metadata-only), the surface SHALL render an
`EmptyState` with explanatory copy.

#### Scenario: Queue reflects the provider's up-next

- **WHEN** the active adapter is Spotify or MusicKit and the provider has a
  populated queue
- **THEN** the queue surface lists those tracks in order, with title, artist,
  and album art per row (rendered via `RowItem`)

#### Scenario: Tap-to-jump in the queue

- **WHEN** the user taps a queued track row while the active provider supports
  jumping ahead in queue
- **THEN** the adapter advances playback to that track and NowPlayingSheet
  shifts the source label to reflect that the user, not the adapter, initiated
  the transition

#### Scenario: No queue surface on metadata-only providers

- **WHEN** the active provider is YouTube
- **THEN** the queue surface renders `EmptyState` ("Queue not available on
  YouTube") rather than an empty list

### Requirement: Companion mode for externally-initiated playback

When the active adapter publishes a track Furioke did not initiate (e.g., the
user started a song in the Spotify app outside Furioke, or skipped tracks via
the Lock Screen, or the adapter advanced its own queue), the app SHALL set
`MusicState.source = .observed(track)` and SHALL run the existing lyric-fetch +
furigana pipeline against that track. The UI SHALL show a "Companion —
{provider}" indicator so the user knows Furioke is following an external player
rather than driving one.

When the observed track is NOT recognized as a saved song and the adapter has
published an incomplete `Track` (empty `name` or empty `artists`), the lyric
load SHALL defer until the adapter publishes a populated shape. While deferred,
the UI SHALL show a "searching" indicator and SHALL NOT flip to an "unavailable"
state.

#### Scenario: Observed playback triggers companion-mode lyric load

- **WHEN** the active adapter publishes a `MusicUpdate` with a `track.id` that
  Furioke did not initiate via `playTrack`
- **THEN** `MusicState.source` becomes `.observed(track)`, the NowPlayingSheet
  calls `/api/lyrics` for the new track, the result runs through the local
  furigana pipeline, and the UI shows the "Companion — {provider}" indicator

#### Scenario: Saved-song query takes precedence

- **WHEN** the playing track matches a saved song's
  `(provider, provider_track_id)`
- **THEN** the lyric query uses the saved song's stored title, artist, album,
  and duration rather than the live `Track` shape — regardless of whether the
  source is `.userInitiated` or `.observed`

#### Scenario: Defer until metadata settles

- **WHEN** the observed track is unrecognized and `track.name` or
  `track.artists` is empty
- **THEN** the lyric load does not fire; the UI shows a "searching" indicator;
  once a populated shape arrives, the load runs exactly once

### Requirement: Active-line highlight follows playback position

The NowPlayingSheet SHALL highlight the lyric line whose timing window contains
the current playback position. The highlight SHALL update on every
playback-position emission from the active adapter and SHALL remain readable in
both light and dark appearance. The active-line scale animation SHALL use
`Motion.pop`.

#### Scenario: Highlight moves with playback

- **WHEN** playback advances from one line's window into the next
- **THEN** the previously-highlighted line returns to its resting state and the
  new line is highlighted within one render frame of the position update

#### Scenario: Highlight survives backgrounding

- **WHEN** the user backgrounds the app during playback and returns
- **THEN** the active-line highlight reflects the position at the moment of
  return, not stale state

### Requirement: Tap-to-seek on a lyric line

The NowPlayingSheet SHALL seek the active provider to a tapped line's start time
when the playing surface supports seeking (Spotify SDK, MusicKit). When the
active provider is metadata-only (YouTube), tapping a line SHALL be a no-op for
seek and SHALL only update visual selection.

#### Scenario: Tap seeks on a playable surface

- **WHEN** the user taps line N while playback is active via the Spotify or
  MusicKit adapter
- **THEN** the adapter's `control(.seek(line.startMs))` is invoked and playback
  moves to that line

#### Scenario: Tap is a no-op for seek on YouTube

- **WHEN** the user taps line N while the active provider is YouTube
- **THEN** no seek is attempted (YouTube is metadata-only on iOS); the tap only
  updates visual selection

### Requirement: Save-to-library button on NowPlayingSheet

NowPlayingSheet SHALL present a **Save** action that inserts the
currently-playing track into the user's `songs` table via the existing save flow
used by `[[song-library]]`. The Save button SHALL be disabled when no track is
playing or when the track is already saved (in which case the button SHALL show
a "Saved" state with a tap-to-open-library affordance).

#### Scenario: Save inserts a saved-song row

- **WHEN** the user taps **Save** while a Spotify or Apple Music track is
  playing
- **THEN** a row is inserted in `songs` carrying the
  `(provider, provider_track_id)` tuple, title, artist, album, and duration; the
  Library tab list reflects the new song

#### Scenario: Save state reflects already-saved

- **WHEN** the currently-playing track is already in the user's `songs` table
- **THEN** the Save action shows a "Saved" state and tapping it opens the
  Library tab with that song highlighted

#### Scenario: Save disabled when no track

- **WHEN** no track is playing or the adapter has not yet published a populated
  track
- **THEN** the Save action is disabled

### Requirement: Translation toggle, cached when possible

NowPlayingSheet SHALL provide a translation toggle that, when enabled, shows
whole-body translations of each lyric line. Translations SHALL be fetched from
`/api/translate` when not in cache and SHALL be served from the local SwiftData
translation cache (see [[ios-offline-cache]]) when available. Cache entries
SHALL be keyed by `(song id, language, model version)`.

#### Scenario: Toggle on, cache hit

- **WHEN** the user enables Translation for a song whose translation is in the
  local cache
- **THEN** the cached translation is rendered immediately without an
  `/api/translate` call

#### Scenario: Toggle on, cache miss

- **WHEN** the user enables Translation for a song whose translation is not in
  the cache and the device is online
- **THEN** `/api/translate` is called, the response is rendered, and the result
  is written to the local cache

#### Scenario: Toggle on, offline cache miss

- **WHEN** the user enables Translation for a song whose translation is not
  cached and the device is offline
- **THEN** the UI shows an inline "translation unavailable offline" message and
  Translation reverts to off; no error toast

### Requirement: MPNowPlayingInfoCenter integration with active-line text

The app SHALL update `MPNowPlayingInfoCenter.default().nowPlayingInfo` on every
active-line change with the rendered text of the active line (kanji with
parenthetical reading interleaved when the reading-style preference is **kana**
or **romaji**; bare kanji when furigana is hidden). Updates SHALL be throttled
to one per active-line change, not per playback-position tick.

#### Scenario: Lock Screen shows active line

- **WHEN** the user views the Lock Screen while a track is playing
- **THEN** the Lock Screen Now-Playing surface shows the current active lyric
  line, formatted per the user's reading-style preference

#### Scenario: Update cadence is per-line, not per-tick

- **WHEN** the active line does not change for 10 seconds while playback
  progresses
- **THEN** `MPNowPlayingInfoCenter` is updated at most once during that window
  (for position metadata); the lyric text is not rewritten on every tick

### Requirement: MPRemoteCommandCenter handles play/pause/skip/seek

The app SHALL register handlers on `MPRemoteCommandCenter` for `playCommand`,
`pauseCommand`, `togglePlayPauseCommand`, `nextTrackCommand`,
`previousTrackCommand`, and `changePlaybackPositionCommand`. Each handler SHALL
delegate to the active adapter's `control` function. Commands SHALL work from
Lock Screen, Control Center, AirPods, and CarPlay.

#### Scenario: Lock-screen play/pause

- **WHEN** the user taps play on the Lock Screen during a session
- **THEN** `MPRemoteCommandCenter`'s `playCommand` handler invokes the active
  adapter's `control(.play)` and playback resumes

#### Scenario: AirPods skip

- **WHEN** the user double-taps an AirPod to skip forward
- **THEN** the `nextTrackCommand` handler invokes the active adapter's
  `control(.next)` and the next track plays

### Requirement: CarPlay Now-Playing template

The app SHALL register a CarPlay scene that presents `CPNowPlayingTemplate`
augmented with the active lyric line as its metadata. Tap-to-seek SHALL NOT be
available in CarPlay (UI is restricted); transport controls SHALL be present via
the standard CarPlay surface.

#### Scenario: CarPlay surface shows lyrics

- **WHEN** the device is connected to CarPlay and a track is playing
- **THEN** the CarPlay Now-Playing surface shows the active lyric line in the
  metadata area

#### Scenario: CarPlay transport controls

- **WHEN** the user uses CarPlay's play / pause / next / previous controls
- **THEN** they route through `MPRemoteCommandCenter` to the active adapter's
  `control` function

### Requirement: Ambient album-art backdrop

The NowPlayingSheet SHALL render the album art of the playing track as an
ambient, blurred backdrop behind the lyrics, mirroring the web `[[now-playing]]`
behavior. The backdrop SHALL not impair readability of the foreground lyric
text.

#### Scenario: Backdrop reflects current track

- **WHEN** a new track begins playing with non-empty album art
- **THEN** the NowPlayingSheet backdrop transitions to a blurred form of the new
  track's album art

#### Scenario: Readability is preserved

- **WHEN** any album-art backdrop is rendered
- **THEN** the foreground lyric text remains legible in both light and dark
  appearance, including over high-contrast album art
