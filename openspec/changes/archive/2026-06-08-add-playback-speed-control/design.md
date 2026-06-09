## Context

Playback runs through the provider-neutral Swift `MusicSource` protocol
(`MusicTypes.swift`). `MusicState` (`@Observable @MainActor`) subscribes to the
active adapter's `updates` stream and is the single source of playback state for
feature/Chrome views. The Now Playing surface (`NowPlayingContent`) is
feature-agnostic Chrome wired from `AppShell`, which reads `MusicState`.

Only YouTube can change rate. It plays in-app via the IFrame Player hosted in a
`WKWebView` (`YouTubePlayerController`), which exposes `setPlaybackRate` /
`getPlaybackRate`. Spotify's iOS SDK (`SPTAppRemote`) and Apple's MusicKit
(`ApplicationMusicPlayer`) expose **no** rate control. So speed is a
per-provider capability — the same shape as the existing `supportsRepeat`.

Position between adapter emissions is interpolated in exactly **one** place:
`MusicState.syncPositionTicker`, which projects `anchorPositionMs + elapsed`
every 250 ms assuming 1× real-time. At 0.5× the audio advances half as fast as
the wall clock, so the scrubber and the active-line highlight (both read
`music.positionMs`) would run ahead between emissions. Rate-awareness is part of
the feature.

## Goals / Non-Goals

**Goals:**

- Let a practising user slow down (or speed up) the active YouTube track from
  Now Playing, with a small fixed set of rates.
- Extend `MusicSource` additively so the capability is provider-neutral.
- Keep the scrubber and active-line highlight accurate at any rate via the
  single interpolation site.
- Hide the control when the active provider can't change rate.

**Non-Goals:**

- Rate control for Spotify or Apple Music (their SDKs can't).
- Persisting a preferred rate across tracks or sessions — rate resets to 1× per
  track.
- Pitch correction or continuous rate input — a fixed option list only.
- A new always-visible transport affordance; the control lives in the existing
  ellipsis options menu.

## Decisions

### 1. Model rate as a capability on the existing contract, mirroring `supportsRepeat`

Add to the protocol: `var supportsPlaybackRate: Bool { get }`, a
`setPlaybackRate(rate: Double)` case on `MusicControl`, and a
`playbackRate: Double` field on `MusicUpdate` (1.0 = normal). `MusicState`
exposes `supportsPlaybackRate` (active adapter's flag, false when none) and a
`playbackRate` it reads off updates. The control flows through the existing
`MusicState.control(_:)` path, so optimistic state and adapter delegation are
reused.

_Alternative considered:_ a dedicated `setPlaybackRate` protocol method.
Rejected — `control(_:)` already centralizes delegation and the
optimistic/reconcile logic; a new method would duplicate that seam.

### 2. YouTube drives the IFrame rate directly through the JS bridge

`YouTubePlayerController.setPlaybackRate(_:)` evaluates
`window.player.setPlaybackRate(<rate>)` — the same direct `window.player.*`
access pattern `stop()` already uses, so no change to the remote
`/embed/youtube` host page is needed. `YouTubeAdapter` tracks `playbackRate` as
state: it sets it on `control(.setPlaybackRate)` and emits immediately, resets
it to 1× in `playTrack` (YouTube otherwise carries the prior video's rate across
a load), and includes it on every `emit(...)`.

**Why track the rate in the adapter rather than poll `getPlaybackRate()`:** the
option list is a fixed subset of YouTube's supported rates, so no clamping
occurs, and the adapter setting it is authoritative. This avoids an extra JS
round-trip on every 400 ms poll tick and keeps the change minimal. (The web app
polls because it reads the rate back defensively; on iOS the deterministic list
makes that unnecessary.)

### 3. Rate-scaled interpolation in the one ticker

`syncPositionTicker` becomes `anchorPositionMs + Int(Double(elapsed) * rate)`,
where `rate` is the live `playbackRate`. `apply(_:)` stores the rate from each
update and `anchor(positionMs:)` is already called on every emission, so a rate
change (which arrives as an emission) re-anchors naturally and position stays
continuous. Because the scrubber and active-line highlight both read
`music.positionMs`, fixing this single site fixes both — simpler than the web,
which has three interpolation sites.

### 4. Speed control lives in the Now Playing ellipsis menu

The ellipsis `optionsMenu` in `NowPlayingContent` already hosts rōmaji /
translation / save. A speed `Picker` (or a labelled submenu) is the calm,
consistent home — no new always-visible chrome on the tight transport bar. It is
gated on `supportsPlaybackRate`, threaded from `AppShell` alongside the existing
toggle closures (`playbackRate`, `supportsPlaybackRate`, `onSetPlaybackRate`),
keeping `NowPlayingContent` feature-agnostic.

_Alternative considered:_ a dedicated speed button beside the transport buttons.
Rejected — it adds permanent chrome for a feature most sessions won't use; the
menu keeps the bar uncluttered. Revisit if usage warrants promotion.

## Risks / Trade-offs

- **Rate persists across `loadVideoById`** → YouTube keeps the last rate on a
  new video; the explicit reset to 1× in `playTrack` neutralizes this. Covered
  by a spec scenario.
- **Embed host page lacks a named helper** → mitigated by calling
  `window.player.setPlaybackRate` directly, matching `stop()`; no remote-page
  dependency.
- **Provider that lies about support** → only the YouTube adapter sets the flag
  true; the contract scenarios pin Spotify/Apple to false, so the control can't
  appear where it can't work.
- **Strict concurrency** → all touched types are already `@MainActor` (the
  controller, adapter, `MusicState`) or `nonisolated` value types
  (`MusicControl`, `MusicUpdate`); adding a `Double` case/field introduces no
  new isolation.

## Migration Plan

Purely additive — no persistence, model, or backend changes. The new
`MusicUpdate` field needs every adapter's emit site updated (Swift structs have
no optional default), so all three adapters set `playbackRate` explicitly
(YouTube its live value, the others `1.0`). Ship in one change; rollback is
reverting the diff.

## Open Questions

- Whether to include 1.75× for symmetry with the slow side. Current choice
  favours a compact menu; easy to widen later.
