## Why

Furioke supports Spotify and Apple Music. Many Japanese songs — especially the
karaoke / 歌ってみた / off-vocal versions people actually sing along to — exist
only on YouTube, not in either licensed catalog, so today a reader cannot play
and read along with them in Furioke at all.

This change adds YouTube as a real, in-app, **account-less video source** —
playback through the official YouTube IFrame Player in a `WKWebView`, search
through an unofficial InnerTube layer hosted in a Supabase Edge Function. Spotify
and Apple Music paths are untouched.

## What Changes

- **Reframe, not "YouTube Music."** A `.youtube` provider presented as a
  **YouTube karaoke / video source**, not as a YT-Music-equivalent streaming
  service. Account-less (`requiresAccount = false`); no Google login.
- **New `YouTubeAdapter` drives in-app playback.** It implements `MusicSource`
  for the `.youtube` provider; `playTrack`/`control` drive a YouTube IFrame
  Player. "View on YouTube" is offered only as a fallback affordance on a hard
  playback failure.
- **New view-backed seam.** A music source MAY require a visible player surface.
  `MusicSource` gains a way to advertise this; `MusicState` stays headless and
  provider-neutral; the WKWebView bridge lives in a `YouTubePlayerController`
  outside the adapter; `NowPlayingSheet` mounts a `YouTubePlayerView` when the
  active source advertises a surface — without hardcoding `.youtube` in the
  view.
- **Search via Supabase Edge Function (InnerTube).** The v1 search path is
  `youtube/search` on a Supabase Edge Function that runs an InnerTube
  (ytmusicapi-style) query and returns provider-neutral track shapes
  (`videoId` + metadata). The official YouTube **Data API is NOT used for search
  in v1** (10k units/day ≈ 100 searches/day for the whole app). The function
  caches `normalizedQuery → results`.
- **Position via `getCurrentTime()` polling** feeding `MusicUpdate.positionMs`,
  reusing `MusicState`'s existing anchor/interpolation — no new position model.
- **IFrame error bridge ships** (previously conditional "if hosted player ships
  in v1"): JS `onError` codes map to `MusicError` and a dead `videoId`
  invalidates its Edge Function cache entry.

## Impact

- **Affected specs:** `music-source` (REMOVE the two placeholder YouTube
  requirements; ADD the video-playback source, the IFrame error bridge, the
  view-backed-source capability, and the InnerTube-search requirements),
  `now-playing` (ADD a video-surface mount + ad-aware lyric sync).
- **Affected code (iOS):** `Music/MusicTypes.swift` (add `.youtube` provider +
  `playerSurface` capability), `Music/MusicState.swift` (surface-aware,
  otherwise unchanged position/control flow), new `Music/YouTubeAdapter.swift`,
  `Music/YouTubePlayerController.swift`, `Music/YouTubePlayerView.swift`; the
  NowPlaying view mounts the surface.
- **Cross-repo (backend/web repo):** the `youtube/search` Supabase Edge Function
  and its cache table are implemented in the separate backend repo. This change
  defines only the **contract** the iOS app depends on.
- **Unchanged:** Spotify (`SpotifyAdapter`) and Apple Music (`MusicKitAdapter`)
  connect, search, and playback paths.

## Non-goals

- Not official YouTube Music support, and not presented as such.
- No official YouTube **Data API** for search in v1.
- No Google / YouTube account login; YouTube Premium does not apply (ads may
  interrupt).
- No background-audio / lock-screen playback for YouTube in v1 — see design.
- No InnerTube logic in the iOS binary.
