## Why

People practising a song — especially fast Japanese tracks — need to slow
playback down to follow the lyrics and sing along. The in-app YouTube IFrame
player supports 0.25×–2× rates, but the app exposes no way to reach it. A
first-class speed control turns the Now Playing surface into a usable practice
tool. This mirrors the change shipped on furioke web.

## What Changes

- Add a **playback speed control** to the Now Playing surface that lets the user
  pick a playback rate (0.25×, 0.5×, 0.75×, 1×, 1.25×, 1.5×, 2×) for the active
  track, surfaced in the existing ellipsis options menu.
- Extend the `MusicSource` contract with a **playback-rate capability**: a
  `supportsPlaybackRate` flag, a `setPlaybackRate` `MusicControl` case, and a
  `playbackRate` field on `MusicUpdate` so the UI can reflect the live rate.
- Implement the capability in the **YouTube adapter / controller** by driving
  the IFrame Player's `setPlaybackRate` through the JS bridge. Spotify and Apple
  Music report `supportsPlaybackRate = false` (their SDKs expose no rate
  control), so the control is hidden for them.
- Make **position interpolation rate-aware**: `MusicState`'s position ticker
  projects `positionMs` forward from the last authoritative value assuming 1×
  real-time, which drifts at non-1× rates between emissions. Scale the
  projection by the current rate so the scrubber and the active-line highlight
  stay aligned.
- The control is gated on `supportsPlaybackRate`, so it only appears when the
  active provider can actually change rate.

## Capabilities

### Modified Capabilities

- `music-source`: the Swift adapter contract gains a playback-rate capability —
  a `supportsPlaybackRate` flag, a `setPlaybackRate` control case, and a
  `playbackRate` field on `MusicUpdate`; the YouTube source implements it while
  Spotify and Apple Music decline it.
- `now-playing`: the Now Playing surface gains a capability-gated speed control,
  and `MusicState`'s position interpolation scales by the active playback rate
  so the scrubber and active-line highlight track the audio at any supported
  rate.

## Impact

- `Furioke/Music/MusicTypes.swift` — `MusicControl`, `MusicUpdate`,
  `MusicSource` capability flag.
- `Furioke/Music/YouTubeAdapter.swift` + `YouTubePlayerController.swift` —
  apply/report rate via the IFrame bridge; reset to 1× on track load.
- `Furioke/Music/SpotifyAdapter.swift`, `MusicKitAdapter.swift` — declare
  `supportsPlaybackRate = false`.
- `Furioke/Music/MusicState.swift` — thread `playbackRate`; scale the position
  ticker projection by rate; expose `supportsPlaybackRate`.
- `Furioke/DesignSystem/Chrome/NowPlayingContent.swift` + `App/AppShell.swift` —
  the speed picker UI and its wiring.
- No new dependencies; no persistence or backend changes.
