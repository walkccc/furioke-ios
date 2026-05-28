## Why

Furioke's iOS Safari experience is degraded by platform constraints the web app
cannot work around: Spotify's Web Playback SDK is disabled on iOS Safari (so
users fall back to 5-second `/me/player` polling), MusicKit JS is brittle, the
Lock Screen and Control Center cannot show the active furigana line, there is no
offline access to previously-fetched lyrics, and there is no App Store presence.
A native SwiftUI app targeting iOS 26+ collapses every one of those limitations:
Spotify's native iOS SDK replaces the poll fallback with real event-driven
playback, MusicKit on iOS provides first-class Apple Music playback,
`MPNowPlayingInfoCenter` displays the active line on the Lock Screen and in
CarPlay, SwiftData caches lyric bodies for offline reading, and SwiftUI's native
`.glassEffect()` on iOS 26 is the actual Liquid Glass design language we have
been hand-rolling in CSS.

## What Changes

- New SwiftUI iOS app, deployment target iOS 26+, distributed through the App
  Store. Sibling client to the existing Next.js web app — the two share the
  Cloudflare Workers backend and Supabase data layer.
- v1 surface: three tabs — **Library** (default), **Search**, **Settings**.
  **NowPlaying is not a tab.** It is the expanded state of a persistent
  `MiniPlayer` that sits above the tab bar via the iOS 26
  `tabViewBottomAccessory` API. Mini-player → NowPlaying expansion morphs
  artwork, title, and artist in place via `matchedGeometryEffect`.
- NowPlaying is a **full-fledged player**, not a passive observer. The user
  picks a track in Library or Search, the iOS app drives the active provider's
  SDK to play it, and the lyric pipeline runs against the track Furioke chose.
  In-app transport (play/pause/prev/next via `TransportButton`), a draggable
  position `Scrubber` with haptic detents, and a queue / up-next surface are
  first-class. Companion mode (showing lyrics for a track the user already
  started in Spotify or Apple Music outside Furioke) remains as a secondary
  fallback so opening the app mid-play still works.
- Native music integration: Spotify iOS SDK (event-driven, no poll mode),
  MusicKit on iOS (no JWT mint), YouTube Music metadata-only (parity with web).
- Spotify on iOS is **fully client-side**: the Spotify iOS SDK holds the access
  token on-device and auto-renews via `SPTSessionManager.renewSession()`. No
  `/api/spotify/sdk-token` round trip during connect. No `provider_tokens` row
  for iOS-only users. Web Spotify continues to use server-mediated tokens; the
  two are independent. Spotify Web API calls from iOS (catalog search, device
  list, device transfer) go direct to `api.spotify.com` using the SDK's current
  access token as Bearer auth.
- Tightened Spotify error vocabulary: `notInstalled` (URL-scheme check),
  `userCancelled` (silent), `handshakeTimeout` (8s SDK silence),
  `transportError` (ECONNREFUSED outside grace window), `renewFailed` (silent;
  Spotify chip flips to its connect-CTA). A 1.5s foreground grace window absorbs
  the first ECONNREFUSED that fires while iOS is resuming Furioke after the
  Spotify app handoff. The catch-all "Spotify isn't running" copy is gone.
- YouTube IFrame error events are bridged into Swift: JS `onError` codes 2 / 5 /
  100 / 101 / 150 surface as `MusicError.unplayable`, `.embedDisabled`,
  `.notFound`, `.regionLocked`. A 3s `playTrack` start-timeout catches a
  forever-buffering stall as `.playbackDidNotStart`. The BUFFERING-state poll
  returns a partial snapshot instead of nil so the UI shows a loading state
  instead of freezing.
- Lock Screen / Control Center / CarPlay now-playing integration via
  `MPNowPlayingInfoCenter`, `MPRemoteCommandCenter`, and `CPNowPlayingTemplate`.
  Displays the currently active furigana line and supports remote transport.
- Offline reading of any previously-fetched song via a SwiftData cache that
  stores the raw LRC lyric body, user corrections, and any cached translation.
  Online-only operations (LRCLIB lookup, translation API, catalog search)
  degrade gracefully.
- Long-press-a-kanji furigana correction surface on NowPlaying, writing through
  to the same `furigana_overrides` Supabase table the web app uses.
- iOS bundles `kuromoji.js` and the kuromoji dictionary as app resources and
  runs the tokenizer locally inside Apple's built-in `JavaScriptCore` framework.
  Tokenizer output and `line_hash` values are byte-identical to the web app
  because the JS code and dictionary files are the same. No backend annotation,
  no `/api/lyrics` contract change.
- Independent Supabase auth on iOS (sign in once per device, JWT in Keychain).
  Deep-link session sharing with the web app is explicitly deferred.
- **iOS design system layer** under `Furioke/Furioke/DesignSystem/` mirrors
  the discipline the web app holds itself to in `AGENTS.md`: `Tokens/` (`Radii`,
  `Spacing`, `Typography`, `Motion`, `Materials`), `Primitives/` (`Surface`,
  `GlassChrome`, `GlassCapsule`, `RowItem`, `TransportButton`, `Scrubber`,
  `SectionHeader`, `EmptyState`), `Chrome/` (`LiquidGlassTabBar`, `MiniPlayer`,
  `NowPlayingSheet`, `NowPlayingContent`, `MiniPlayerExpansion`). Feature views
  compose primitives instead of inline styling. The chrome-vs-content material
  split is enforced at the type level: `Surface` only accepts opaque `Material`
  tokens, `GlassChrome` only accepts `Glass` role tokens.

## Capabilities

### New Capabilities

- `ios-app-shell`: SwiftUI app entry point; root sign-in gate; 3-tab `AppShell`
  (Library default, Search, Settings); persistent `MiniPlayer` above the tab bar
  via `tabViewBottomAccessory`; mini-player → `NowPlayingSheet` expansion via
  shared `matchedGeometryEffect` namespace owned by `AppShell`; expansion state
  machine; one-time onboarding hint; iOS 26+ deployment target; native Liquid
  Glass adoption with chrome-vs-content split; theme / language preferences;
  Library as the home surface.
- `ios-design-system`: tokens, primitives, and chrome layer. Establishes the
  chrome-vs-content material contract at the type level so misuse fails to
  compile. Feature views compose against this layer rather than inline-styling.
- `ios-auth`: Supabase sign-in on iOS via `ASWebAuthenticationSession`, JWT
  stored in Keychain, sign-out flow, session refresh.
- `ios-music-source`: Swift `MusicSource` adapter contract and three
  implementations — Spotify iOS SDK (fully client-side, SDK-managed tokens),
  MusicKit, YouTube-metadata — mirroring the web `[[music-source]]` contract
  surface so feature code is provider-neutral. Hardened error vocabulary,
  Spotify connect state machine with grace window and handshake timeout, YouTube
  error bridging.
- `ios-furigana`: bundled `kuromoji.js` + dict, executed via `JavaScriptCore`,
  with the built-in seed correction map and the user's `furigana_overrides`
  applied locally. The same `line_hash` algorithm used on the web, ported to
  Swift and verified byte-equivalent.
- `ios-now-playing`: in-app playback control via design-system primitives
  (`TransportButton`, `Scrubber`, `GlassCapsule`); user-initiated track loading
  from Library and Search via a single `NowPlayingState.play(track:)` entry
  point; active-line display; line-tap-to-seek; save-to-library; ambient
  album-art backdrop; companion fallback for externally-initiated playback;
  `MPNowPlayingInfoCenter` / `MPRemoteCommandCenter` / CarPlay integration.
  Delivered as the expanded state of the persistent mini-player owned by
  `AppShell`.
- `ios-search`: provider catalog search across the active connected provider,
  with the save-to-library flow and tap-to-play that routes through
  `NowPlayingState.play(track:)` (no tab switch).
- `ios-offline-cache`: SwiftData schema and access layer caching saved songs,
  raw LRC lyric bodies, furigana overrides, and translation results. Defines the
  read-through, write-through, and invalidation rules.
- `ios-furigana-corrections`: long-press-on-kanji reading-override surface,
  writing through to `furigana_overrides` via the existing backend.

### Modified Capabilities

None. iOS uses the existing `/api/lyrics` contract unchanged and runs the same
`kuromoji.js` + dict the web app ships, inside `JavaScriptCore`. The Spotify
server routes (`/api/spotify/sdk-token`, `/api/spotify/devices`,
`/api/spotify/tracks`, `/api/spotify/search`) remain unchanged for the web
client and simply lose their iOS callers.

## Impact

- New Swift codebase, placed at `ios/Furioke/` as a sibling target in this
  repository so the backend, schema migrations, and capability specs stay
  co-located. Bundle identifier `com.magicparklabs.Furioke`; springboard display
  name `furioke` (lowercase, matching brand voice).
- iOS bundle resources: `kuromoji.umd.js` (~3MB) and the kuromoji dict files
  (~8MB) copied from the web app's `node_modules/kuromoji` and `public/dict/`
  directories. ~11MB added to the iOS binary; invisible against typical iOS app
  sizes.
- Backend: no changes. `/api/lyrics` response shape unchanged. Web client
  unchanged.
- Deployment: separate App Store pipeline, Apple Developer account ($99/year),
  code-sign + provisioning profiles. Cloudflare Workers backend deploy is
  untouched.
- New external dependencies: `supabase-swift`, Spotify iOS SDK
  (`SpotifyiOS.xcframework`), Apple MusicKit (system framework). No new
  server-side dependencies. `JavaScriptCore` ships with iOS, no SPM dependency.
- Schema: no new tables. `provider_tokens` continues to store the web app's
  server-OAuth Spotify refresh token; iOS does not write to this table.
- Auth on iOS is independent of the web session in v1 (sign in once per device).
  Cross-device session sharing is deferred.
- Storage architecture: SwiftData (local read-through cache, purged on
  sign-out). No CloudKit — Supabase is the single source of cross-device sync.
