## ADDED Requirements

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
