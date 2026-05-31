## ADDED Requirements

### Requirement: NowPlaying mounts a video surface for view-backed sources

`NowPlayingSheet` SHALL mount an embedded `YouTubePlayerView` when the active
music source advertises a video `playerSurface`, and SHALL render the existing
ambient blurred-artwork backdrop otherwise. The decision SHALL be driven by the
active source's `playerSurface` capability, NOT by comparing the provider
against `.youtube`. The embedded player SHALL be visible (the IFrame Player
requires a visible surface) and SHALL be laid out so the synchronized furigana
lyric view remains the primary reading surface — the video occupies a bounded
region rather than replacing the lyrics.

#### Scenario: Video source shows an embedded player

- **WHEN** the active source's `playerSurface` is a video surface and a track is
  playing
- **THEN** `NowPlayingSheet` mounts a visible `YouTubePlayerView` bound to the
  shared `YouTubePlayerController`, and the lyric view renders alongside it

#### Scenario: Headless source keeps the artwork backdrop

- **WHEN** the active source's `playerSurface` is `.none`
- **THEN** `NowPlayingSheet` renders the ambient blurred-artwork backdrop and
  mounts no embedded web player

### Requirement: Lyric sync tolerates video position via getCurrentTime polling

For a video-backed source, playback position SHALL be sourced by polling the
IFrame Player's `getCurrentTime()` and emitting it on `MusicUpdate.positionMs`,
reusing the existing `MusicState` anchor/interpolation so the active-line
highlight advances smoothly between polls. No separate position pathway SHALL be
added for video sources. During an ad or buffering interval — when
`getCurrentTime()` reports a timeline that is not the song's content — the
active-line highlight SHALL freeze (hold its last content position) rather than
jump, and SHALL resume when content playback resumes.

#### Scenario: Active line advances during YouTube playback

- **WHEN** a YouTube track is playing
- **THEN** the adapter emits `MusicUpdate.positionMs` from polled
  `getCurrentTime()`, `MusicState` interpolates between polls, and the lyric
  active-line highlight advances in time with the audio

#### Scenario: Active line freezes during an ad

- **WHEN** the IFrame Player enters an ad / buffering state and
  `getCurrentTime()` no longer reflects the song's content timeline
- **THEN** the active-line highlight holds its last content position and does
  not desync, resuming once content playback continues

### Requirement: No lock-screen control for YouTube in v1

For a video-backed source, the app SHALL NOT populate `MPNowPlayingInfoCenter`
or register `MPRemoteCommandCenter` transport handlers, because YouTube IFrame
audio does not play in the background or over the lock screen in v1. Spotify and
Apple Music lock-screen integration SHALL remain unchanged.

#### Scenario: YouTube does not present a dead lock-screen control

- **WHEN** a YouTube track is the current track and the device locks
- **THEN** no Furioke now-playing info or transport control is presented on the
  lock screen for that track (avoiding a control that cannot drive the suspended
  web player)

#### Scenario: Spotify and Apple Music lock-screen unchanged

- **WHEN** the active source is Spotify or Apple Music
- **THEN** the existing `MPNowPlayingInfoCenter` / `MPRemoteCommandCenter` /
  CarPlay integration behaves exactly as before this change
