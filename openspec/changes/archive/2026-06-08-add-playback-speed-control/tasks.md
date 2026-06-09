## 1. Extend the MusicSource contract

- [x] 1.1 Add `setPlaybackRate(rate: Double)` to the `MusicControl` enum in
      `MusicTypes.swift`
- [x] 1.2 Add `var supportsPlaybackRate: Bool { get }` to the `MusicSource`
      protocol (next to `supportsRepeat`)
- [x] 1.3 Add `let playbackRate: Double` to `MusicUpdate`

## 2. Implement the capability in the YouTube source

- [x] 2.1 Add `setPlaybackRate(_ rate: Double)` to `YouTubePlayerController`,
      evaluating `window.player.setPlaybackRate(<rate>)` directly (matching
      `stop()`)
- [x] 2.2 In `YouTubeAdapter` set `supportsPlaybackRate = true` and track a
      `playbackRate` property (default 1.0)
- [x] 2.3 Handle `.setPlaybackRate(rate)` in the adapter's `control` → call the
      controller, store the rate, emit; reset rate to 1.0 in `playTrack`
- [x] 2.4 Include `playbackRate` on every `emit(...)`

## 3. Declare no support on the other adapters

- [x] 3.1 Set `supportsPlaybackRate = false` in `SpotifyAdapter`; return
      `.failure(.unsupported)` for `.setPlaybackRate` in its `control`; emit
      `playbackRate: 1.0`
- [x] 3.2 Set `supportsPlaybackRate = false` in `MusicKitAdapter`; return
      `.failure(.unsupported)` for `.setPlaybackRate` in its `control`; emit
      `playbackRate: 1.0`

## 4. Thread the rate through MusicState

- [x] 4.1 Add a `playbackRate` property to `MusicState`, fed from
      `MusicUpdate.playbackRate` in `apply(_:)` (default 1.0)
- [x] 4.2 Expose `supportsPlaybackRate` on `MusicState` (active adapter's flag,
      false when none)
- [x] 4.3 Scale `syncPositionTicker`'s projection by the live rate
      (`anchorPositionMs + Int(Double(elapsed) * rate)`); verify a rate change
      re-anchors continuously
- [x] 4.4 Update `showUserInitiated` / `resetPlaybackState` to keep
      `playbackRate` coherent (reset to 1.0)

## 5. Build the Now Playing speed control

- [x] 5.1 Add a fixed rate option list constant
      (`0.25, 0.5, 0.75, 1, 1.25, 1.5, 2`)
- [x] 5.2 Add a capability-gated speed `Picker`/submenu to the ellipsis
      `optionsMenu` in `NowPlayingContent.swift`, marking the active rate, with
      an accessible label
- [x] 5.3 Thread `playbackRate`, `supportsPlaybackRate`, and `onSetPlaybackRate`
      from `AppShell` into `NowPlayingContent`, wiring the handler to
      `music.control(.setPlaybackRate(rate:))`

## 6. Verify

- [ ] 6.1 Code compiles under Swift 6 strict concurrency (developer runs the
      build; do not run xcodebuild)
- [ ] 6.2 Manually verify on YouTube: selecting 0.5× slows audio, the scrubber
      and active-line highlight stay aligned, and the control reflects the live
      rate
- [ ] 6.3 Confirm the speed control is absent for Spotify and Apple Music, and
      that a new track starts at 1×
