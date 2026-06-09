## ADDED Requirements

### Requirement: Playback speed control on NowPlaying

The NowPlaying surface SHALL present a playback-speed control that lets the user
choose the active track's rate from a fixed set of options: 0.25×, 0.5×, 0.75×,
1×, 1.25×, 1.5×, and 2×. Selecting an option SHALL dispatch
`control(.setPlaybackRate(rate:))`, and the control SHALL mark the active rate
as selected. The control SHALL render only when the active provider reports
`supportsPlaybackRate = true`; when the provider cannot change rate, the surface
SHALL NOT show the speed affordance.

#### Scenario: User slows a track down

- **WHEN** a YouTube track is playing at 1× and the user opens the speed control
  and selects 0.5×
- **THEN** the rate-setting control is dispatched, the player begins playing at
  half speed, and the control marks 0.5× as the active option

#### Scenario: Control reflects the live rate

- **WHEN** the active track's reported `playbackRate` is `0.75`
- **THEN** the speed control shows 0.75× as the selected option

#### Scenario: Rate-incapable provider hides the control

- **WHEN** the active provider is Spotify or Apple Music
  (`supportsPlaybackRate = false`)
- **THEN** the NowPlaying surface does not render any playback-speed control

### Requirement: Position interpolation scales by playback rate

`MusicState` SHALL project `positionMs` forward between authoritative adapter
emissions scaled by the current playback rate. At rate r, the projected position
MUST advance by r times the elapsed wall-clock since the last anchor, so the
scrubber and the active-line highlight track the audio — not the wall clock — at
any supported rate. A rate change SHALL re-anchor the projection so position
stays continuous.

#### Scenario: Highlight tracks audio at half speed

- **WHEN** a synced YouTube track plays at 0.5× between two position emissions
- **THEN** the projected position advances by ~half the elapsed wall-clock and
  the active lyric line and scrubber stay aligned with the audio instead of
  running ahead

#### Scenario: Position stays continuous across a rate change

- **WHEN** the user changes the rate from 1× to 0.5× mid-playback
- **THEN** the projected position does not jump; it continues from the current
  position at the new rate
