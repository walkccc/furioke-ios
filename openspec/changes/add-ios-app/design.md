## Context

Furioke today is a Next.js 16 web app on Cloudflare Workers with a Supabase
Postgres backend. The web app's iOS Safari path is materially degraded: the
Spotify Web Playback SDK is disabled by Apple on iOS Safari, so iOS users fall
back to 5-second `/me/player` polling with a 1.5s `seekGate` workaround;
MusicKit-JS is brittle; the Lock Screen and CarPlay cannot show the active
furigana line; PWA storage is uncertain for offline lyric reading; and there is
no App Store presence.

This change adds a native SwiftUI iOS 26+ client that shares the existing
backend and Supabase data model. The two clients become siblings of the same
Workers API, not a fork. The web app remains the curation surface when typing or
larger screens are wanted; the iOS app is where the user actually listens and
reads.

An earlier draft of this design proposed moving kuromoji tokenization into a
backend service so both clients could consume an annotated payload. On
re-examination the `line_hash` "drift" risk used to justify that move was
overstated — `line_hash` is computed on lyric line text after NFKC normalization
and edge-punct strip, not on tokenizer output, so it does not depend on the
tokenizer. The remaining concern (cross-tokenizer reading divergence) is
sidestepped entirely by running the **same** `kuromoji.js` and the **same** dict
on both clients. iOS does that via Apple's built-in `JavaScriptCore` framework,
bundling the JS file and dict as app resources. This skips the backend refactor
and the kuromoji-on-Workers spike.

## Goals / Non-Goals

**Goals:**

- Ship an iOS 26+ SwiftUI app to the App Store with three tabs — Library
  (default), Search, Settings — and a persistent mini-player above the tab bar
  that expands into a full NowPlaying sheet via shared `matchedGeometryEffect`.
  Together they deliver the core "listen + read with furigana + translate" loop.
- Replace Spotify Web Playback SDK / poll fallback with the native Spotify iOS
  SDK on iPhone, with event-driven playback state and SDK-managed tokens.
- Replace MusicKit-JS with native MusicKit, removing the server-signed
  developer-token mint for native consumers.
- Display the active furigana line on the Lock Screen, Control Center, and
  CarPlay via `MPNowPlayingInfoCenter` and `CPNowPlayingTemplate`.
- Allow reading of previously-fetched lyrics fully offline, including the user's
  furigana overrides and any cached translation.
- Tokenize lyrics locally on iOS via `JavaScriptCore` + bundled `kuromoji.js` +
  bundled dict, sharing the web app's tokenizer output byte-identically without
  requiring any backend annotation service.
- Adopt SwiftUI's native iOS 26 Liquid Glass (`.glassEffect()` /
  `GlassEffectContainer`) instead of recreating it in CSS, with a typed
  chrome-vs-content split that mirrors the web app's discipline.

**Non-Goals:**

- iPad-optimised layouts and Mac Catalyst — iPhone only in v1. SwiftUI lets
  Catalyst be added later without architectural change.
- Pre-iOS-26 deployment. The user has no installed base, and `.glassEffect()`
  alone is a strong enough reason to target 26+.
- Cross-device session sharing (sign in on web, be signed in on iOS).
  Independent Supabase auth on each device for v1.
- A text-editor surface on iOS. The web app's "editor" is itself just the lyric
  viewer + line selection — that role is filled by NowPlaying on iOS. Saving a
  song from the web app's paste-URL flow remains web-only.
- Push notifications. Nothing to notify for at v1; APNs can land in a later
  change.
- Server-side furigana annotation. Both clients tokenize locally with the same
  kuromoji.js + dict.
- Backend changes. `/api/lyrics`, `/api/translate`, `/api/spotify/*`,
  `/api/youtube/*`, `/api/lyric-anchors` are all consumed as-is — and iOS drops
  several of them (`/api/spotify/sdk-token`, `/api/spotify/devices`,
  `/api/spotify/tracks`, `/api/spotify/search`) in favor of direct
  `api.spotify.com` calls.
- CloudKit sync. SwiftData is purely a local read-through cache; cross-device
  data flows through Supabase.
- Furigana correction UI on web in this change. The web's existing UX stays;
  only iOS gains the long-press surface.
- The SPA paradigm on iOS. The native tab idiom stays; the borrowed SPA element
  is the persistent mini-player's "always know what's playing" continuity.

## Decisions

### D1 — Run `kuromoji.js` inside iOS via `JavaScriptCore`; no backend annotation

The iOS app bundles `kuromoji.umd.js` (~3MB) and the kuromoji dictionary files
(~8MB) as app resources. A Swift `KuromojiBridge` instantiates a `JSContext`,
evaluates the bundled JS, overrides kuromoji's default fetch to load dict files
from the iOS bundle, and exposes a `tokenize(text:)` Swift API. The bridge is
module-scope cached so the dict is loaded once per app session.

The same `line_hash` algorithm used in the web's `lib/lyrics/line-hash.ts` is
ported to Swift. Because `line_hash` operates on lyric line text
post-normalization (NFKC → strip whitespace → strip edge punctuation →
sha256-truncated), it does not depend on the tokenizer at all; the Swift port
is mechanical.

The built-in seed correction map is shared between web and iOS via
`lib/lyrics/seed.json`, copied into the iOS bundle by an Xcode build phase.

**Alternatives considered:**

- _Server-side annotation:_ rejected. The `line_hash` drift argument was wrong —
  `line_hash` is computed on lyric line text, not on tokens. The remaining
  concern (cross-tokenizer reading divergence) is fully eliminated by shipping
  the same JS + same dict on both clients.
- _Native Swift tokenizer_ (e.g., `mecab-swift`, `SudachiKit`): rejected.
  Different tokenizer output than kuromoji at edge cases; we would have to
  maintain a divergent reading map.
- _`WKWebView` island_: rejected. The lyric surface is the screen the user
  stares at most; embedding web there defeats the point of going native.

**Why it wins:** identical tokenizer output to web, no backend work, no
cross-implementation drift surface, sub-second tokenization after the first dict
load (~500ms first-call cost), ~11MB added to the iOS binary.

### D2 — Independent Supabase auth on iOS, JWT in Keychain

The iOS app drives its own Supabase OAuth via `ASWebAuthenticationSession`,
stores the resulting JWT in the iOS Keychain
(`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), and refreshes via
`supabase-swift`. There is no shared session with the web app.

**Alternatives considered:**

- _Deep-link the web sign-in back into iOS via `furioke://auth?token=…`_ —
  cleaner UX, but it requires registering a universal link, securing the token
  transit, and reasoning about session invalidation across devices. Deferred to
  a later change.

**Why it wins:** smallest surface, no new server code, no universal-link
configuration, no token-transit threat model in v1.

### D3 — Spotify on iOS is fully client-side; SDK manages tokens

The iOS app does **not** route Spotify auth through Furioke's server. The
Spotify iOS SDK (`SPTSessionManager` + `SPTAppRemote`) drives the deep-link auth
flow with the Spotify app, holds the resulting access token on-device, and
auto-renews via `SPTSessionManager.renewSession()`. The adapter never calls
`/api/spotify/sdk-token`, and no `provider_tokens` row is created for iOS-only
users.

Spotify Web API calls from iOS (catalog search, device list, device transfer,
track-metadata resolution) issue directly against `api.spotify.com` using the
SDK's current access token as Bearer auth. On a 401, the adapter calls
`SPTSessionManager.renewSession()`; on renewal failure, the adapter silently
re-issues `initiateSession()` (a no-op deep-link when the user is still
authorized in the Spotify app, a one-tap reconnect otherwise) and on second
failure surfaces `MusicError.renewFailed` — the Spotify chip flips back to its
connect CTA without an intrusive toast.

This is a deliberate divergence from an earlier draft of this design (which had
iOS share the web's server-stored token row). The divergence is consistent with
the v1 decision that "Auth on iOS is independent of the web session." Web
Spotify is unaffected and continues to use server-mediated tokens.

**Alternatives considered:**

- _Server-mediated tokens on iOS_ (the earlier draft): rejected. Splitting
  scope-tracking across server and device, two parallel token-management
  stories, and the extra `/api/spotify/sdk-token` round trip during connect all
  add surface for negligible gain — the SDK already has a designed
  token-management story.
- _Let the SDK do all auth without our involvement_: this is what we're doing.
  The previous "server-mediated" middle ground was the rejected option.

**Why it wins:** preserves the v1 "independent sessions" promise without
partially bridging it; one token-management story per platform; one fewer server
round trip during connect; SDK-native lifecycle.

### D4 — Spotify connect state machine + grace window + error vocabulary

The Spotify connect path replaces `withCheckedContinuation` with an explicit
state machine (`idle → linking → connected | failed(reason)`) driven by SDK
delegate events. Double-resume becomes impossible because there is no
continuation to resume twice. The state machine has one input (events from the
delegate) and one output (the final connect result).

A 1.5s **foreground grace window** after iOS resumes Furioke (post-Spotify-app
handoff) absorbs the first `ECONNREFUSED` from the SDK transport — a known race
during the handoff resume. A 1500ms `lastForegroundAt` window classifies the
error as "ignore + retry once" instead of "transport failure."

An **8s handshake timeout** safety net surfaces `MusicError.handshakeTimeout` if
the SDK delegate never fires, so the UI never sticks on "Checking…".

Error vocabulary on connect:

| Reason             | When                                              | User-facing copy                                                   |
| ------------------ | ------------------------------------------------- | ------------------------------------------------------------------ |
| `notInstalled`     | `spotify://` URL scheme does not resolve          | "Spotify isn't installed."                                         |
| `userCancelled`    | User declined the Spotify auth screen             | (silent — no toast)                                                |
| `handshakeTimeout` | 8s elapsed without delegate callback              | "Spotify didn't respond. Try again."                               |
| `transportError`   | 2nd `ECONNREFUSED` outside the grace window       | "Couldn't connect to Spotify. Open the Spotify app and try again." |
| `renewFailed`      | `renewSession()` failed AND silent re-init failed | (silent — Spotify chip surfaces "Connect" CTA)                     |
| `cancelled`        | User backed out before deep-link returned         | (silent)                                                           |

The catch-all "Spotify isn't running on this device" copy is removed.

### D5 — YouTube error bridge and play-start timeout

The IFrame Player's `onError` JS event is bridged into a Swift handler. JS error
codes map to:

| YT error code | Reason emitted                   |
| ------------- | -------------------------------- |
| 2             | `MusicError.unplayable`          |
| 5             | `MusicError.embedDisabled`       |
| 100           | `MusicError.notFound`            |
| 101 / 150     | `MusicError.regionLocked`        |
| (timeout 3s)  | `MusicError.playbackDidNotStart` |

`MusicUpdate` carries an optional `playbackError: MusicError?` field. The UI
surfaces a toast and the adapter clears its pending-track state so the user can
retry without a manual reset. The 3s play-start timeout catches a
forever-buffering stall; buffering deliberately does not cancel the timeout (the
timeout is designed to catch a stalled load, not a slow load).

The BUFFERING-state `snapshot()` returns a partial `MusicUpdate` with the
pending track id and `isPlaying: false` instead of nil, so the now-playing
surface renders a loading indicator instead of freezing.

### D6 — MusicKit on iOS uses Apple-native auth, not the server JWT route

`/api/apple-music/token` (which mints a developer JWT for MusicKit JS) is not
needed for native MusicKit. `MusicAuthorization.request()` and the `MusicKit`
Swift framework authenticate the user's Apple ID directly. The route stays in
place for the web app; iOS does not call it.

Apple Music ships as a first-class provider alongside Spotify with the same
"very clean" philosophy: system authorization, in-app playback via
`ApplicationMusicPlayer.shared`, direct catalog search via
`MusicCatalogSearchRequest`. No Furioke server endpoint is in the loop on iOS
for Apple Music.

### D7 — YouTube on iOS: metadata-only, parity with web

The YouTube provider remains metadata-only on iOS (search via
`/api/youtube/search`, resolve via `/api/youtube/videos`). No in-app playback.
The web app's `[[youtube-playback]]` behavior is web-specific (IFrame embed); on
iOS, YouTube songs appear in search and library but indicate "metadata-only —
open in YouTube" rather than attempting playback.

### D8 — SwiftData for the offline cache; cache raw LRC bodies

The local cache is SwiftData with four entities:

```
SongEntity        id, provider, providerTrackId, title, artist, album,
                  durationMs, savedAt
LyricBodyEntity   songId, lrclibId, bodyText (raw LRC as fetched),
                  fetchedAt
OverrideEntity    userId, kanji, reading, source (local | synced)
TranslationEntity songId, language, bodyJson, modelVersion, generatedAt
```

`LyricBodyEntity` stores the raw LRC body — exactly what `/api/lyrics` returns.
On every render the iOS furigana pipeline runs over the cached body, applies the
user's overrides, and produces the annotated form in memory. There is no
persisted annotated payload; the kuromoji tokenization is fast enough after dict
load (sub-millisecond per line) that re-tokenizing on every render is cheaper
than maintaining a parallel cache.

Reads are cache-first when offline, server-first when online with cache
write-through. Cache entries have a 30-day TTL to mirror the web app's IndexedDB
translation cache. A 90-day janitor evicts entries on app launch. On sign-out,
all per-user entities are purged.

**No CloudKit.** Supabase already provides cross-device sync (the authoritative
`songs`, `furigana_overrides`, `lyric_line_anchors`, `model_usage` rows). Adding
CloudKit on top would create two sync layers racing each other and would scope
sync to the user's Apple ID rather than their Furioke (Google-OAuth) identity.

### D9 — App architecture: orchestrator + slice observables, mirroring the web

The iOS app follows the same orchestrator pattern as the web app: one
`@Observable` model per concern (e.g. `MusicState`, `LibraryState`,
`NowPlayingState`, `PreferencesState`) injected at the root and consumed via
`@Environment`. High-frequency state (playback position) lives in its own
observable so it doesn't re-render the library or settings.

### D10 — Repository layout: monorepo with an `ios/` directory

The Xcode project lives at `ios/Furioke.xcodeproj` in this repo, with sources at
`ios/Furioke/` — sibling to the Next.js `app/`. Backend, capability specs,
schema migrations, and iOS code stay co-located in one git history. The existing
Cloudflare deploy pipeline is untouched.

**Alternative:** separate `furioke-ios` repo. Rejected because shared seed JSON
(`lib/lyrics/seed.json`), shared backend contract, and synchronised release
notes all benefit from co-location.

### D11 — Three tabs, persistent mini-player, NowPlaying as expansion

The signed-in `AppShell` presents three tabs (Library, Search, Settings) with
Library default. NowPlaying is **not** a tab. A persistent `MiniPlayer` sits
above the tab bar via the iOS 26 `tabViewBottomAccessory` API, visible whenever
a track is loaded against the active provider (including paused state). Tap or
drag-up on the mini-player expands the `NowPlayingSheet`; the sheet's chevron /
drag-down collapses it back. Expansion morphs artwork, title, and artist via a
`matchedGeometryEffect` namespace owned by `AppShell`.

An expansion state machine
(`collapsed → expanding → expanded → collapsing → collapsed`) serializes the
morph so rapid expand/collapse cycles don't interleave animations. Inputs in the
two transitional phases are ignored.

The `NowPlayingState.play(track:)` entry point is the single seam from Library /
Search into playback: it calls the active adapter's `playTrack`, sets
`MusicState.source = .userInitiated(track)`, starts the lyric load without
waiting for `playerStateDidChange` echo, and calls
`MiniPlayerExpansion.requestExpand()`. Library and Search never switch tabs to
"go to NowPlaying" — they request expansion of the persistent mini-player.

NowPlaying is a full-fledged player (`TransportButton` × 4, draggable `Scrubber`
with haptic detents at 25/50/75%, queue / up-next, ambient album-art backdrop)
that drives the active provider's SDK. Companion mode (opening Furioke while a
track is already playing in Spotify or Apple Music) remains as a fallback: when
the adapter publishes a track the app did not initiate, the lyric load runs
against that track and the UI shows a "Companion — {provider}" indicator.

**Alternatives considered:**

- _Four tabs with NowPlaying as a peer destination (the earlier draft):_
  rejected. Apple Music, Spotify, and Pocket Casts all model NowPlaying as a
  state (mini-player → expansion), not a tab. Requiring an explicit tab switch
  to "go check the music" contradicts the platform mental model.
- _SPA paradigm with a single scrollable canvas (matching the web):_ rejected.
  The Liquid Glass tab bar is the showcase surface for `.glassEffect()` in iOS
  26 — abandoning tabs would discard the platform's most expressive visual
  mechanic, and cross-platform navigation "consistency" is a false virtue when
  each ergonomic context (mouse + page vs. thumb + tab) calls for different
  idioms.
- _Built-in player only, no companion path:_ rejected. The companion path is
  almost free given the adapter contract already publishes updates regardless of
  who initiated playback, and removing it would break the
  "open-Furioke-while-already-listening" flow the web app supports today.

**Why it wins:** matches the web app's dual-mode philosophy (SDK + poll →
built-in + companion on iOS); the tab idiom preserves per-tab scroll state the
SPA paradigm would have to re-engineer; the borrowed mini-player gives the SPA's
"always know what's playing" continuity without abandoning tabs; lets the lyric
load start at track-select rather than at SDK echo (one fewer perceived
round-trip on every song change).

### D12 — iOS design system layer

The iOS app's design system mirrors the discipline the web app holds itself to
in `AGENTS.md`. The layer lives under `Furioke/Furioke/DesignSystem/`:

```
DesignSystem/
├─ Tokens/
│  ├─ Radii.swift        .sm=8 .md=12 .lg=16 .xl=20 .xxl=28
│  ├─ Spacing.swift      4-pt grid: .xs=4 .s=8 .m=12 .l=16 .xl=24 .xxl=32
│  ├─ Materials.swift    glass roles: chromeGlass, capsuleTier, controlTier
│  │                     opaque roles: contentSurface, popoverSurface
│  ├─ Motion.swift       .pop, .ease, .sheet
│  └─ Typography.swift   pageTitle, sectionTitle, body, metadata,
│                        lyricActive, lyricRest, furigana
│
├─ Primitives/
│  ├─ Surface              opaque content card (forms, dialogs)
│  ├─ GlassChrome          .glassEffect() wrapper with role
│  ├─ GlassCapsule         pill (provider chip, device chip)
│  ├─ RowItem              library/search row: artwork + 2-line + trailing
│  ├─ TransportButton      play/pause/skip with SymbolEffect choreography
│  ├─ Scrubber             position bar + seek gesture + haptics
│  ├─ SectionHeader        title + optional action
│  └─ EmptyState           icon + title + body + action
│
└─ Chrome/
   ├─ LiquidGlassTabBar    3-tab bar via tabViewBottomAccessory + glass
   ├─ MiniPlayer           persistent above tab bar; drag-up = NowPlaying
   ├─ NowPlayingSheet      full-screen expansion of MiniPlayer
   ├─ NowPlayingContent    body inside the sheet
   └─ MiniPlayerExpansion  observable expansion state machine
```

**Chrome vs content split** — same rule the web app holds itself to, enforced at
the type level: `Surface` accepts only opaque `Material` tokens and
`GlassChrome` accepts only `Glass` role tokens. Misuse fails at the call site:

| Surface                       | Material                            |
| ----------------------------- | ----------------------------------- |
| Tab bar                       | `Materials.chromeGlass`             |
| Mini-player                   | `Materials.chromeGlass`             |
| NowPlayingSheet header chrome | `Materials.chromeGlass`             |
| Provider chip, device chip    | `Materials.capsuleTier`             |
| Transport buttons (on chrome) | `Materials.controlTier`             |
| Settings form sections        | `Materials.contentSurface` (opaque) |
| Override editor sheet         | `Materials.contentSurface` (opaque) |
| Dropdowns / menus             | `Materials.popoverSurface` (opaque) |
| Destructive confirms          | `Materials.popoverSurface` (opaque) |

`AppShell` is the single composition root that knows about the tab bar +
mini-player + sheet layout. Feature views never reach in.

**Motion budget** is exactly three roles — `Motion.pop` (transport tap feedback,
button presses, active-line scale), `Motion.ease` (incidental state
transitions), `Motion.sheet` (mini-player expansion, sheet presentation).
Feature code never writes `withAnimation(.spring(...))`.

**Accessibility floor** — every primitive declares an `accessibilityLabel` by
construction; `Typography` tokens use relative text styles so all surfaces scale
with Dynamic Type; `.glassEffect()` degrades to opaque material under
`accessibilityReduceTransparency`; `matchedGeometryEffect` degrades to a
cross-fade under `accessibilityReduceMotion` — both are system behaviors
documented at the primitive level rather than custom-handled per feature.

### D13 — Active-line surfacing on Lock Screen

`MPNowPlayingInfoCenter.nowPlayingInfo[MPMediaItemPropertyComments]` (or the iOS
26-introduced lyric-line key if available — see O1) is updated on every
active-line change. The text is the **rendered furigana-bearing line** (kanji
with parenthetical reading interleaved, falling back to bare kanji if the
reading-style preference is `kana-only` or `off`). Update cadence is throttled
to one update per active-line change, not per progress tick.

### D14 — Naming

- Bundle identifier: `com.magicparklabs.Furioke` (lowercase reverse-DNS).
- Xcode project / module / folder: `Furioke` (PascalCase — Swift module
  convention).
- Springboard display name: `furioke` (lowercase, via `CFBundleDisplayName`,
  matching web brand voice).

## Risks / Trade-offs

- **[Risk]** `JavaScriptCore` memory footprint while the tokenizer is alive —
  ~30–50MB for the JS engine + parsed dict. → **Mitigation:** load on first
  tokenize call (lazy), keep the `JSContext` module-scope cached for the rest of
  the session, tear down on `applicationDidReceiveMemoryWarning` and
  re-instantiate on next need.

- **[Risk]** First-call tokenization latency (~500ms to load and parse the
  dict). → **Mitigation:** kick off a background load when the app enters the
  NowPlaying surface (before the user's first song needs tokenizing). Show a
  small "Preparing readings…" indicator only if the first lyric load actually
  has to wait.

- **[Risk]** Spotify iOS SDK requires the Spotify app to be installed for some
  flows. → **Mitigation:** detect installation via
  `UIApplication.canOpenURL("spotify://")`; if absent, surface
  `MusicError.notInstalled` before any SDK transport attempt. Lyric display
  still works against any external Spotify playback via the companion path.

- **[Risk]** iOS / web Spotify auth divergence. A user who connects on web must
  connect again on iOS (one tap if still authorized in the Spotify app). →
  **Trade-off accepted:** this is the explicit v1 decision that "Auth on iOS is
  independent of the web session." Cross-device session sharing is a deferred
  feature.

- **[Risk]** SDK quietly stops renewing. If the Spotify SDK fails to renew the
  session and the silent re-initiate also fails (e.g., user revoked access in
  Spotify settings), playback stops mid-track. → **Mitigation:** surface
  `renewFailed` by flipping the Spotify chip to its connect-CTA state; do not
  show a toast; preserve the current track on the NowPlaying surface so the user
  can resume after reconnecting.

- **[Risk]** Liquid Glass on iOS 26 is new; some `glassEffect()` edge cases
  (over photographic backdrops, over scrolling content) have known quirks. →
  **Mitigation:** the team has already shipped a hand-rolled liquid glass on the
  web (per `feedback_glass_layering`); the same compositional lessons (chrome
  must be over content, refraction-only not lightening) translate. Use Apple's
  recipes first; reach for `GlassEffectContainer` only when chrome groups.

- **[Risk]** Mini-player → NowPlaying matched-geometry morph is the most
  ambitious animation in the app. Risk of broken intermediate states during
  rapid expand-collapse. → **Mitigation:** serialize via the expansion state
  machine (`collapsed → expanding → expanded → collapsing → collapsed`); ignore
  inputs in transitional states.

- **[Risk]** IA change perception — users who learned an earlier four-tab layout
  may briefly hunt for the NowPlaying tab. → **Mitigation:** a one-time
  onboarding hint on first launch points at the mini-player; the hint dismisses
  on first interaction and never returns.

- **[Risk]** Saving a song from NowPlaying on iOS goes through direct Spotify
  Web API calls / MusicKit catalog for metadata enrichment. If a track is
  missing fields the save flow on web tolerates, iOS may diverge. →
  **Mitigation:** the metadata-settling pattern (defer until `name` + `artists`
  are populated) is the source of truth; iOS adopts it exactly.

- **[Risk]** Furigana-correction long-press on iOS writes to
  `furigana_overrides`; the web app reads from the same table. If the web UI
  doesn't refresh after an iOS correction, users see stale readings on web until
  next document open. → **Mitigation:** the web app's existing
  `LyricsFuriganaProvider` re-reads on document open; real-time sync (Supabase
  Realtime subscription) is deferred.

- **[Risk]** App Store review may surface issues with the Spotify SDK
  (Apple-Spotify rivalry has historically caused friction). → **Mitigation:**
  Spotify's iOS SDK has been App-Store-accepted in many shipping apps; follow
  Spotify's documented guidelines; have a fallback "view in Spotify" path that
  doesn't depend on the SDK.

## Migration Plan

There is no backend or web-app migration. iOS development starts directly
against the existing `/api/lyrics`, `/api/translate`, `/api/youtube/*`, and
`/api/lyric-anchors` contracts plus direct `api.spotify.com` calls. The web app
is unchanged.

Sequence:

1. Set up the Xcode project (manual step — Apple Developer account, bundle ID,
   signing).
2. Land the iOS design system layer (Tokens → Primitives → Chrome) before any
   feature view consumes it.
3. Land the iOS local furigana pipeline (`KuromojiBridge`, `LineHashSwift`, seed
   map).
4. Land auth, music sources, then NowPlaying (via the design system) — the spine
   of the product.
5. Lock Screen / CarPlay, Search, Library, offline cache, corrections — in any
   order, mostly independent.
6. App Store submission.

App Store binaries are append-only: a regression ships as a follow-up version.
There is no rollback in the traditional sense; the closest analog is "remove
from sale" while a fix is prepared.
