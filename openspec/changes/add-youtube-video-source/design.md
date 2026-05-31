# Design — YouTube video / karaoke source

## Context

`MusicState` is a provider-neutral `@Observable` that owns playback state and
delegates transport to whichever `MusicSource` adapter is active. The two
existing adapters (`SpotifyAdapter`, `MusicKitAdapter`) are **headless** — they
play through an out-of-process app (Spotify) or a system player
(`ApplicationMusicPlayer`), so no view is required. YouTube is different: the
only ToS-compliant playback route on iOS is the **YouTube IFrame Player**, which
must render in a **visible** `WKWebView`. So this is the first source that needs
a player surface, and that is the central design tension.

This change introduces YouTube as that first view-backed source and resolves the
seam cleanly, without disturbing the headless Spotify and Apple Music adapters.

## Goals / Non-goals

- **Goal:** YouTube playback + search behind the existing `MusicSource` /
  `MusicState` seam, with lyric active-line sync working unchanged.
- **Goal:** Keep `MusicState` headless and provider-agnostic; keep the InnerTube
  grey area off the iOS binary.
- **Non-goal:** Background audio, lock-screen `MPNowPlayingInfoCenter`
  integration for YouTube, ad suppression, official Data API search.

## Decisions

### Decision 1 — View seam: capability flag + external controller (not associated-type protocol)

Two options were considered:

```
Option A — ViewBackedMusicSource: MusicSource { associatedtype PlayerView: View }
  ✗ Associated-type View protocols are painful: existentials (`any MusicSource`)
    can't carry the associated type, the registry [MusicProvider: any MusicSource]
    breaks, type erasure boilerplate spreads.

Option B (CHOSEN) — capability flag on MusicSource; WKWebView bridge lives in a
  separate YouTubePlayerController; NowPlaying mounts the view.
```

`MusicSource` gains a neutral capability:

```swift
enum MusicPlayerSurface { case none, video }   // extensible
protocol MusicSource {                          // + existing members
    var playerSurface: MusicPlayerSurface { get }   // default .none
}
```

- Spotify / MusicKit return `.none` → NowPlaying renders the existing artwork
  backdrop.
- YouTube returns `.video` → NowPlaying mounts a `YouTubePlayerView`.

**NowPlaying must NOT branch on `provider == .youtube`.** It branches on
`activeSource.playerSurface`. This keeps the "feature code never names a vendor"
invariant the `music-source` spec depends on. The `YouTubePlayerController`
(owns the `WKWebView` + JS bridge) is constructed at the composition root and
injected into both the `YouTubeAdapter` (which drives it) and the view (which
displays it) — so the adapter stays the control authority and the view is a thin
`UIViewRepresentable`.

### Decision 2 — Position: poll `getCurrentTime()`, emit `MusicUpdate`, reuse existing interpolation

`MusicState` already solves "provider only reports on discrete events" for
Spotify by anchoring on each authoritative `MusicUpdate.positionMs` and
projecting forward at 250 ms (`anchor` + `syncPositionTicker`,
`MusicState.swift:177-195`). YouTube fits this model with **no `MusicState`
change**:

```
YouTubePlayerController ──poll getCurrentTime() every ~400ms──▶ YouTubeAdapter
        │                                                            │
        └── onStateChange (PLAYING/PAUSED/BUFFERING/ENDED) ──────────┤
                                                                     ▼
                                          adapter emits MusicUpdate(positionMs,…)
                                                                     ▼
                                   MusicState.apply() → anchor() + ticker smooths
                                                                     ▼
                                          lyrics read positionMs → active line
```

Poll cadence ~400 ms (cheaper than 250 ms; the ticker interpolates the gap). We
do **not** add a second position pathway.

### Decision 3 — Search: Supabase Edge Function running InnerTube; iOS calls a stable contract

```
YouTubeAdapter.searchCatalog(query)                       (iOS — stable)
        │  POST {function}/youtube/search { q, limit }
        ▼
Supabase Edge Function  ── InnerTube (ytmusicapi-style) ──▶ youtube internal API
        │  cache: normalizedQuery → [ {videoId,title,artists,durationMs,thumb} ]
        ▼
provider-neutral MusicTrack[]  (provider = .youtube, providerTrackID = videoId)
```

Rationale (the load-bearing risk decision): InnerTube is an **unstable private
API** — Google rotates client keys, changes request shapes, adds bot checks /
`po_token`. Putting it in the iOS binary means every breakage needs an App Store
review to fix. In the Edge Function it is **hotfixable server-side**, gives a
natural **cache** layer, and keeps the grey logic out of the shipped binary. The
official Data API is rejected for search: 10k units/day ÷ 100 units per
`search.list` ≈ 100 searches/day for the entire app, and user OAuth does not
move quota to the user.

**Cross-repo:** the Edge Function and its cache table live in the separate
backend/web repo. This change owns the **contract** only (request/response
shape, error codes, cache-invalidation call).

### Decision 4 — `MusicTrack` needs no new field; `videoId` IS `providerTrackID`

`MusicTrack` already carries `(provider, providerTrackID, uri, …)`. For YouTube,
`providerTrackID = videoId` and `MusicProvider.youtube.playbackURI(forTrackID:)`
returns the embed/watch form. No `YouTubeTrack` subtype, no model migration —
the Search tab and Library persist `(provider, providerTrackID)` exactly as they
do for Spotify/Apple Music.

### Decision 5 — Account-less "connection"

YouTube has no auth. `connect()` resolves `.success` immediately and
`getConnection()` reports `.connected(.youtube)` once the source is selected (or
once the WKWebView IFrame reports `onReady`). `getAccount()` returns `nil`.
Selecting YouTube in Settings is therefore effectively instant — no deep link,
no system prompt.

### Decision 6 — Ads desync lyrics and invalidate the cache (closing the loop)

- **During an ad**, `getCurrentTime()` reports the _ad's_ timeline. The adapter
  detects ad/buffering state via `onStateChange` and emits updates that hold the
  song position (or flags `isPlaying=false`/buffering) so the lyric highlight
  **freezes** instead of jumping. Active-line sync resumes when content resumes.
- **Hard playback errors** (codes 100/101/150 = removed / region-locked / embed
  off) mean the cached `videoId` is now unplayable. The adapter both surfaces a
  `MusicError` on `MusicUpdate.playbackError` **and** signals the Edge Function
  to invalidate that query's cache entry, so the next search re-resolves a live
  video rather than handing back the dead one.

### Decision 7 — Foreground-only is acceptable for karaoke (v1)

YouTube IFrame audio suspends when the app backgrounds or the screen locks, and
there is no ToS-compliant background-audio path. For a **karaoke /
reading-along** feature this is tolerable: the user is looking at the furigana
lyrics on-screen, which is inherently a foreground, screen-on activity. v1
documents this as a known limitation rather than fighting it. (Spotify/Apple
Music keep their normal background behavior — this limitation is YouTube-only.)

## Risks / Trade-offs

| Risk                                                             | Mitigation                                                                                                                                                                                  |
| ---------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **InnerTube search breaks** when Google changes its internal API | Logic lives in the Supabase Edge Function → hotfix without App Store review; cache softens transient breakage; iOS shows a graceful "YouTube search is temporarily unavailable" empty state |
| **Ads interrupt playback** and desync lyrics                     | Detect ad state via `onStateChange`; freeze active-line during ads; accept ads as a documented limitation (no Premium without login)                                                        |
| **Dead `videoId`** cached from a prior search                    | IFrame `onError` → `MusicError` + Edge Function cache invalidation; "view on YouTube" fallback affordance                                                                                   |
| **WKWebView autoplay blocked** without a user gesture            | Configure `allowsInlineMediaPlayback = true` and `mediaTypesRequiringUserActionForPlayback = []`; the play originates from the user's tap on a track row, which is the gesture              |
| **No background / lock-screen audio**                            | Documented v1 limitation; karaoke is a foreground activity; do not populate `MPNowPlayingInfoCenter` for YouTube to avoid a lock-screen control that does nothing                           |
| **App Store review** (3rd-party content / unofficial API)        | Official IFrame playback is the sanctioned embed path; framed as karaoke video, not a YT-Music clone; InnerTube is server-side, not in the binary                                           |
| **3s forever-buffering stall**                                   | Existing spec rule reused: emit `playbackDidNotStart` and clear pending `currentVideoId` so the next play isn't blocked                                                                     |

## Open questions

1. **Search cache TTL** in the Edge Function — fixed TTL vs. invalidate-on-error
   only? (Leaning: long TTL + error-driven invalidation, since query→video
   mappings are stable until a video dies.)
2. **Provider switching mid-playback** — when the user switches away from
   YouTube, `teardownActive()` must also tear down the
   `YouTubePlayerController`/WKWebView. Where does the controller's lifecycle
   hang — composition root, or created/destroyed per selection? (Leaning:
   created at root, `load`/`stop` on select/teardown.)
3. Do we want a **lyric-offset nudge** specific to YouTube (karaoke videos often
   have baked-in intros), or rely on the existing tap-to-seek? (Defer to v2.)
