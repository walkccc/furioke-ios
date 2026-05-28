## 1. iOS project scaffolding

- [x] 1.1 Create `Furioke.xcodeproj` via Xcode New Project (SwiftUI App
      template, iOS 26 deployment target, iPhone idiom only, language Swift,
      storage SwiftData)
- [x] 1.2 Configure Apple Developer team, bundle identifier
      (`com.magicparklabs.Furioke`), `CFBundleDisplayName = "furioke"`,
      provisioning profile, and code-signing in Xcode project settings
- [x] 1.3 Add `URL Types` entry for the `furioke://` custom scheme in Info.plist
- [x] 1.4 Add background modes capability for `audio` playback (remote
      notifications deferred to a later change)
- [x] 1.5 Enable MusicKit on the App ID (developer.apple.com → Identifiers →
      App Services → MusicKit), add `NSAppleMusicUsageDescription` to
      Info.plist, and add the Spotify iOS SDK XCFramework
- [x] 1.6 Add `supabase-swift` as an SPM dependency

## 2. iOS design system (Tokens → Primitives → Chrome)

The design system lands before any feature view consumes it. Each phase is
independently shippable and produces no visual change on its own.

### 2a — Tokens

- [x] 2a.1 Create `Furioke/Furioke/DesignSystem/Tokens/`
- [x] 2a.2 `Radii.swift` — `.sm=8 .md=12 .lg=16 .xl=20 .xxl=28`
- [x] 2a.3 `Spacing.swift` — 4-pt grid `.xs=4 .s=8 .m=12 .l=16 .xl=24 .xxl=32`
- [x] 2a.4 `Materials.swift` — split into glass roles (`chromeGlass`,
      `capsuleTier`, `controlTier`) and opaque roles (`contentSurface`,
      `popoverSurface`)
- [x] 2a.5 `Motion.swift` — `.pop`, `.ease`, `.sheet` spring presets only
- [x] 2a.6 `Typography.swift` — `pageTitle`, `sectionTitle`, `body`, `metadata`,
      `lyricActive`, `lyricRest`, `furigana`, all built on relative SwiftUI text
      styles so they scale with Dynamic Type

### 2b — Primitives

- [x] 2b.1 `Surface.swift` — opaque content card; type-level constraint that
      accepts only opaque `Material` tokens
- [x] 2b.2 `GlassChrome.swift` — `.glassEffect()` wrapper; type-level constraint
      that accepts only `Glass` role tokens (misuse fails to compile)
- [x] 2b.3 `GlassCapsule.swift` — pill (provider chip, device chip)
- [x] 2b.4 `RowItem.swift` — library/search row: artwork + 2-line + trailing
- [x] 2b.5 `TransportButton.swift` — `.bounce` SymbolEffect on tap, `.scale`
      while held; `accessibilityLabel` required by construction
- [x] 2b.6 `Scrubber.swift` — position bar + seek gesture + `.light` haptic
      detents at the 25 / 50 / 75% points
- [x] 2b.7 `SectionHeader.swift` — title + optional trailing action
- [x] 2b.8 `EmptyState.swift` — icon + title + body + optional action

### 2c — Chrome

- [x] 2c.1 `LiquidGlassTabBar.swift` — three-tab `TabView` over Library / Search
      / Settings, wearing `Materials.chromeGlass`
- [x] 2c.2 `MiniPlayer.swift` — collapsed-state row hosted by
      `tabViewBottomAccessory`; reads from `MusicState`
- [x] 2c.3 `NowPlayingSheet.swift` — full-height sheet container with glass
      header
- [x] 2c.4 `NowPlayingContent.swift` — the inner body rendered inside the sheet
      (header chip, artwork, source chip, lyric column, scrubber, transport row)
- [x] 2c.5 `MiniPlayerExpansion.swift` — observable expansion state machine
      `collapsed → expanding → expanded → collapsing → collapsed`; ignores
      inputs in transitional phases
- [x] 2c.6 `App/AppShell.swift` — composition root owning the
      `matchedGeometryEffect` namespace for the artwork / title / artist morph
      between `MiniPlayer` and `NowPlayingSheet`

## 3. iOS local furigana pipeline (kuromoji.js via JavaScriptCore)

- [x] 3.1 Copy `kuromoji.umd.js` from `node_modules/kuromoji/build/` into
      `Furioke/Resources/Kuromoji/` and add as a bundle resource (Copy
      Bundle Resources build phase) — present as `Resources/Kuromoji/kuromoji.js`;
      auto-bundled by the project's synchronized folder group (no pbxproj edit)
- [x] 3.2 Copy the kuromoji dict files from `public/dict/` into
      `Furioke/Resources/KuromojiDict/` and add as bundle resources — present and
      auto-bundled by the synchronized folder group
- [x] 3.3 Confirm `lib/lyrics/seed.json` is the shared source of truth for the
      built-in correction map (web app already imports it; the iOS bundle build
      phase consumes the same file) — NOTE: this is a separate `furioke-ios` repo
      (web app at `../furioke`), so a true monorepo share is impossible. Per user
      decision, `seed.json` is vendored byte-identical into `Resources/seed.json`
- [x] 3.4 Add an Xcode build phase that copies `lib/lyrics/seed.json` into the
      iOS bundle as `Resources/seed.json` — superseded: the vendored copy is
      auto-bundled by the synchronized folder, so no build phase is needed
- [x] 3.5 Implement `KuromojiBridge.swift` — wraps a `JSContext` that loads
      `kuromoji.umd.js`, overrides the dict-fetch shim to read from the bundle,
      exposes a `tokenize(text:) async -> [Token]` Swift API
- [x] 3.6 Make `KuromojiBridge` module-scope cached so the dict is parsed once
      per session; expose a `purge()` for memory-warning handling
- [x] 3.7 Implement `LineHash.swift` — port the web's `lib/lyrics/line-hash.ts`
      algorithm (NFKC, strip whitespace, strip edge punct, sha256 truncate to
      128 bits) into pure Swift
- [x] 3.8 Implement `CorrectionMap.swift` — load `seed.json` from the bundle,
      merge with user overrides loaded from `OverrideEntity`, apply greedy
      longest-match phrase substitution
- [x] 3.9 Implement `FuriganaPipeline.swift` — given raw LRC body and a
      `CorrectionMap`, return `[AnnotatedLine]` with surface, reading, and
      `lineHash` per line

## 4. iOS auth (Supabase, Keychain)

- [x] 4.1 Implement `KeychainSessionStore` wrapping the iOS Keychain with
      `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` for the Supabase
      access + refresh tokens
- [x] 4.2 Implement `AuthService` using `supabase-swift` configured with the
      Furioke Supabase project URL and anon key
- [x] 4.3 Implement the `ASWebAuthenticationSession` sign-in flow targeting the
      Supabase OAuth URL for Google, with `furioke://auth/callback` redirect
- [x] 4.4 Handle the OAuth callback: parse the URL fragment, extract tokens,
      persist to Keychain, transition the app's root state to the signed-in
      surface
- [x] 4.5 Implement transparent refresh-on-expiry using `supabase-swift`'s
      session refresh; on `invalid_grant`, clear Keychain and transition to
      sign-in
- [x] 4.6 Implement sign-out: clear Keychain, purge per-user SwiftData entities,
      clear in-memory Spotify session, forget MusicKit authorization, transition
      to sign-in surface

## 5. iOS music sources

### 5a — Contract and dispatch

- [ ] 5a.1 Define the `MusicSource` Swift protocol mirroring the web contract
      (provider id, requiresAccount, supportsRepeat, getConnection, optional
      getAccount, updates AsyncStream, connect, disconnect, control, playTrack,
      resolveTracks)
- [ ] 5a.2 Define the `MusicError` enum: `notInstalled`, `userCancelled`,
      `handshakeTimeout`, `transportError`, `renewFailed`, `cancelled`,
      `unplayable`, `embedDisabled`, `notFound`, `regionLocked`,
      `playbackDidNotStart`, `unsupported`, `needsReconnect`,
      `providerRejected(String)`
- [ ] 5a.3 Define `MusicUpdate` carrying playback snapshot fields and an
      optional `playbackError: MusicError?` for mid-session failures
- [ ] 5a.4 Implement `MusicState` observable that delegates to the active
      adapter and is injected as `@Environment` for feature views; carries
      `lastPlaybackError` derived from adapter emissions

### 5b — Spotify adapter (fully client-side)

- [ ] 5b.1 Implement `SpotifyiOSAdapter` using `SPTSessionManager` +
      `SPTAppRemote`. SDK holds the access token on-device; no
      `/api/spotify/sdk-token` round trip; no `provider_tokens` row created for
      iOS-only users
- [ ] 5b.2 Replace `withCheckedContinuation`-based connect with an explicit
      state machine: `idle → linking → connected | failed(reason)`. The state
      machine is the only path that resolves the connect operation, preventing
      double-resume and never-resume
- [ ] 5b.3 URL-scheme miss (`canOpenURL("spotify://") == false`) short- circuits
      to `MusicError.notInstalled` before the SDK is touched
- [ ] 5b.4 Implement the 1.5s foreground grace window: ignore the first
      `ECONNREFUSED` from the SDK transport within 1500ms of a UIScene
      foreground transition; retry connect once silently before surfacing
      failure
- [ ] 5b.5 Implement the 8s handshake timeout safety net so the UI never sticks
      on "Checking…"
- [ ] 5b.6 Remove the catch-all "Spotify isn't running" copy. Map each failure
      reason to a distinct user message per the design's error vocabulary
- [ ] 5b.7 Implement `SpotifyWebAPIClient` — direct `api.spotify.com` calls
      using the SDK's current access token as Bearer auth
- [ ] 5b.8 Route device list, device transfer, and `resolveTracks` through
      `SpotifyWebAPIClient` (no `/api/spotify/devices`, `/api/spotify/control`,
      or `/api/spotify/tracks` calls from iOS)
- [ ] 5b.9 Implement 401 → `renewSession()` → silent re-init flow in a single
      `withRefreshedToken<T>` helper; on second failure emit `renewFailed`

### 5c — MusicKit adapter

- [ ] 5c.1 Implement `MusicKitAdapter` using `MusicKit`: authorization via
      `MusicAuthorization.request()`; `ApplicationMusicPlayer.shared` plays
      in-app; `MusicCatalogSearchRequest` for search
- [ ] 5c.2 `SystemMusicPlayer` (or the appropriate MusicKit player API) state
      changes → `MusicUpdate` emissions
- [ ] 5c.3 Map the no-subscription path to a useful user message

### 5d — YouTube metadata adapter

- [ ] 5d.1 Implement `YouTubeMetadataAdapter`: search via `/api/youtube/search`,
      resolve via `/api/youtube/videos`. `control` and `playTrack` return
      `MusicError.unsupported`
- [ ] 5d.2 If a hosted IFrame player ships in v1, bridge the JS `onError` event
      into a Swift handler. Map codes 2 / 5 / 100 / 101 / 150 to
      `MusicError.unplayable`, `embedDisabled`, `notFound`, `regionLocked`
- [ ] 5d.3 Add a 3s `playTrack` start-timeout for the IFrame path; surface
      `playbackDidNotStart` and clear `currentVideoId` on failure
- [ ] 5d.4 Return a partial snapshot (pending track id, `isPlaying: false`) from
      the BUFFERING-state `snapshot()` instead of nil so the UI renders a
      loading indicator instead of freezing

### 5e — Provider selection

- [ ] 5e.1 Implement single-active-provider selection in Settings, persisted in
      `UserDefaults`; restore on launch; do not auto-connect inactive providers
      in the background
- [ ] 5e.2 Tear down the previous adapter exactly once on provider switch (no
      leaked subscriptions)

## 6. iOS app shell (3 tabs + mini-player + sheet)

- [ ] 6.1 Implement `RootView` to switch between sign-in surface and `AppShell`
      based on `AuthService` state
- [ ] 6.2 Implement `AppShell` with the three tabs in order: Library (default),
      Search, Settings — no NowPlaying tab
- [ ] 6.3 Apply native `.glassEffect()` to the tab bar via `LiquidGlassTabBar`;
      verify refraction-only treatment per the memory on glass layering
- [ ] 6.4 Host `MiniPlayer` above the tab bar via the iOS 26
      `tabViewBottomAccessory` API; visible iff a track is loaded against the
      active provider; hidden when not connected
- [ ] 6.5 Wire tap and drag-up on `MiniPlayer` to call
      `MiniPlayerExpansion.requestExpand()` and present `NowPlayingSheet`
- [ ] 6.6 Wire chevron-tap and drag-down on `NowPlayingSheet` to collapse via
      the expansion state machine
- [ ] 6.7 Share a `@Namespace` between `MiniPlayer` and `NowPlayingSheet` owned
      by `AppShell` for the `matchedGeometryEffect` artwork / title / artist
      morph
- [ ] 6.8 Implement the one-time onboarding hint pointing at the mini-player on
      first launch; persist dismissal via `@AppStorage`; never reappear
- [ ] 6.9 Implement theme override (Light / Dark / System) in Settings,
      persisted in `UserDefaults`
- [ ] 6.10 Implement language override (en / ja / zh) with system-locale
      default; persist in `UserDefaults`; localize all v1 UI strings
- [ ] 6.11 Implement the sign-in surface with the Google OAuth entry point using
      the `GlassChrome` primitive for the sign-in button

## 7. iOS Library tab

- [ ] 7.1 Implement the Library view that reads from `SongEntity` and renders
      saved songs most-recently-saved first using `RowItem`
- [ ] 7.2 Tap-to-play: call `NowPlayingState.play(track:)` and
      `MiniPlayerExpansion.requestExpand()` — do not switch tabs
- [ ] 7.3 Implement the empty-state surface using `EmptyState` with copy
      directing to Search or to playing in the connected provider
- [ ] 7.4 Library sync on launch and on tab activation: pull from `songs`,
      reconcile by `(provider, providerTrackId)`, remove server-deleted rows

## 8. iOS Search tab

- [ ] 8.1 Implement the Search view with a glass search field at the top and a
      debounced (~300ms) search field that dispatches to the active adapter's
      search
- [ ] 8.2 Render provider-neutral results via `RowItem` (title, artist, album,
      duration, "Saved" / "Save" affordance)
- [ ] 8.3 Tap-to-play (Spotify, MusicKit) routes through
      `NowPlayingState.play(track:)` and `MiniPlayerExpansion.requestExpand()`
- [ ] 8.4 Tap-to-view (YouTube) opens the YouTube app or web URL; does not
      attempt in-app playback
- [ ] 8.5 Save from result rows reuses the saved-song write path from the
      NowPlaying surface
- [ ] 8.6 Implement the no-provider-connected empty state via `EmptyState` with
      a jump-to-Settings affordance

## 9. iOS NowPlaying surface (expanded mini-player)

- [ ] 9.1 Implement `NowPlayingState` with a `Source` enum
      (`.userInitiated(Track)` / `.observed(Track)` / `.idle`) so the lyric load
      can start at user-initiated track select rather than at SDK echo, and so
      the UI can label externally-initiated playback as companion mode
- [ ] 9.2 Implement `NowPlayingState.play(track:)` as the single entry point
      from Library / Search: calls active adapter's `playTrack`, sets
      `source = .userInitiated`, kicks off the lyric load immediately, and calls
      `MiniPlayerExpansion.requestExpand()`
- [ ] 9.3 Render the source chip via `GlassCapsule`: "Playing on Spotify" /
      "Playing on Apple Music" / "Companion — {provider}"
- [ ] 9.4 Render transport via `TransportButton` (play / pause / previous /
      next); delegate to active adapter's `control`; visually disabled (~35%
      opacity) when unsupported, not hidden; `Motion.pop` animations
- [ ] 9.5 Render position via `Scrubber`: drag preview without affecting
      playback; release calls `control(.seek)`; suppress incoming `positionMs`
      emissions during drag and for a short settling window after release;
      haptic `.light` impact at 25 / 50 / 75% detents
- [ ] 9.6 Implement queue / up-next surface reading from the active adapter's
      queue state (Spotify SDK `getPlayerState` queue, MusicKit
      `SystemMusicPlayer.queue.entries`); empty state via `EmptyState` for
      YouTube
- [ ] 9.7 Implement companion-mode lyric load: when the adapter publishes an
      update with a track Furioke did not initiate, set
      `source = .observed(track)` and run the lyric-fetch + furigana pipeline
      against it (with the deferral rule for incomplete `Track` shapes — defer
      until `name` + `artists` populate)
- [ ] 9.8 Lyric query rule: use saved-song metadata when the track is in the
      user's library (matched by `(provider, providerTrackId)`); else use the
      live `Track` shape — same as the web `[[now-playing]]`
- [ ] 9.9 Run the fetched raw LRC body through `FuriganaPipeline` to produce
      annotated lines; render via a SwiftUI lyric view that applies the user's
      reading-style preference (kana / romaji / off)
- [ ] 9.10 Active-line highlight bound to the playback position emission, with
      `Motion.pop` scale on the active line
- [ ] 9.11 Tap-to-seek on a lyric line for playable providers; visual-only tap
      for YouTube
- [ ] 9.12 Save action that POSTs to the existing saved-song endpoint and
      reflects "Saved" state when the song is already in `songs`
- [ ] 9.13 Translation toggle with SwiftData cache lookup before
      `/api/translate`; "translation unavailable offline" on cache miss while
      offline
- [ ] 9.14 Ambient album-art backdrop with blur, preserving foreground lyric
      legibility in both light and dark appearance

## 10. iOS Lock Screen, Control Center, CarPlay

- [ ] 10.1 Implement `NowPlayingInfoUpdater` that writes
      `MPNowPlayingInfoCenter.default().nowPlayingInfo` on every active-line
      change, throttling updates to one per active-line transition
- [ ] 10.2 Implement the active-line text formatter (kanji + parenthetical
      reading per user preference) for the Lock Screen surface
- [ ] 10.3 Register `MPRemoteCommandCenter` handlers for play, pause, toggle,
      next, previous, seek; delegate each to the active adapter's `control`
- [ ] 10.4 Add a CarPlay scene declaration in Info.plist and implement
      `CPNowPlayingTemplate` with the active lyric line in metadata
- [ ] 10.5 Verify Lock Screen, Control Center, AirPods, and CarPlay each
      exercise the remote command handlers correctly on a physical device

## 11. iOS offline cache (SwiftData)

- [ ] 11.1 Define `SongEntity`, `LyricBodyEntity`, `OverrideEntity`, and
      `TranslationEntity` SwiftData models with the indexes specified in the
      `[[ios-offline-cache]]` spec
- [ ] 11.2 Implement the read-through cache wrapper around `/api/lyrics`
      returning raw LRC body (online cache-hit + bg revalidate; online miss
      writes through; offline hit returns; offline miss is a graceful empty
      state)
- [ ] 11.3 Implement the read-through cache wrapper around `/api/translate`
- [ ] 11.4 Implement the 30-day TTL stale-check and the 90-day janitor that runs
      on app launch
- [ ] 11.5 Implement the per-user purge invoked from sign-out

## 12. iOS furigana corrections

- [ ] 12.1 Implement the long-press gesture on rendered kanji tokens that opens
      the inline reading editor without triggering line-tap-seek
- [ ] 12.2 Implement the inline reading editor with the kanji surface, focused
      reading field, **Apply to all songs** toggle, confirm, and cancel; the
      editor surface uses `Materials.popoverSurface` (opaque)
- [ ] 12.3 Local rendering update on confirm (re-runs `FuriganaPipeline` with
      the updated override map; no `/api/lyrics` round-trip), reconciling
      matching annotations when **Apply to all songs** is enabled
- [ ] 12.4 Override persistence: write `OverrideEntity` with `source = local`,
      POST to the backend, transition to `source = synced` on success
- [ ] 12.5 Offline override queueing: on reconnect, run the queued upload and
      transition local rows to `synced`

## 13. Motion + accessibility polish

- [ ] 13.1 Audit `withAnimation` call sites and ensure every animation
      references `Motion.pop`, `Motion.ease`, or `Motion.sheet` (no bespoke
      springs)
- [ ] 13.2 Verify `accessibilityReduceTransparency` falls back gracefully on
      every glass surface (system behavior — confirm on device)
- [ ] 13.3 Verify `accessibilityReduceMotion` collapses matched-geometry morph
      to cross-fade (system behavior — confirm on device)
- [ ] 13.4 Confirm every interactive primitive carries an `accessibilityLabel`
      by construction; audit feature views for any `Button` or `Image` action
      without an inherited label
- [ ] 13.5 Dynamic Type — verify lyric column legibility at the largest
      accessibility sizes; tune `Spacing.xs` line gap if needed

## 14. App Store submission

- [ ] 14.1 Produce App Store screenshots for all required iPhone display sizes
      covering Library, NowPlaying (with annotation visible), Search, and
      Settings
- [ ] 14.2 Write App Store description, keywords, support URL, privacy policy
      URL, and category selection
- [ ] 14.3 Configure App Store Connect privacy disclosures: which data is
      collected (Supabase email, Spotify scopes, MusicKit usage), whether it
      leaves the device, and tracking declaration
- [ ] 14.4 Configure entitlements for MusicKit and verify Spotify SDK
      entitlement is in place
- [ ] 14.5 Submit for App Store review
