# Tasks — YouTube video / karaoke source

Ordered as thin vertical slices. Each top-level group is independently
reviewable; Spotify and Apple Music paths must stay untouched throughout.

> Status note: all iOS code is implemented. Group 2's server function (2.2/2.3)
> lives in the separate backend/web repo (`furioke`) and is now implemented
> there as the `youtube-search` Supabase Edge Function plus the
> `youtube_search_cache` table (migration `008_youtube_search_cache.sql`). Group
> 8 is on-device/simulator verification — `xcodebuild` is unavailable in this
> environment, so those remain to be run (8.6 validated).

## 1. Provider + model plumbing

- [x] 1.1 Add `.youtube` case to `MusicProvider` (`MusicTypes.swift`):
      `displayName = "YouTube"`, `playbackURI(forTrackID:)` returns the
      embed/watch form for a `videoId`.
- [x] 1.2 Add the provider-neutral `MusicPlayerSurface` enum (`.none`, `.video`)
      and `var playerSurface: MusicPlayerSurface { get }` to the `MusicSource`
      protocol with a `.none` default (protocol extension).
- [x] 1.3 Confirm `SpotifyAdapter` and `MusicKitAdapter` inherit
      `playerSurface == .none` (no code change beyond the default).
- [x] 1.4 Verify `MusicTrack` needs no new field (videoId = `providerTrackID`);
      `MusicProvider` is `Codable` so a `.youtube` track round-trips through the
      Library; `resolveTracks` rebuilds via the Edge Function resolve route.

## 2. Edge Function contract (cross-repo: backend/web)

- [x] 2.1 Define the `youtube-search` request/response contract (q, limit →
      `[{videoId,title,artists,durationMs,thumbnailUrl}]`) — documented on
      `YouTubeSearchClient` (the iOS-side contract the function must satisfy).
- [x] 2.2 Implement the InnerTube query + `normalizedQuery → results` cache in
      the Supabase Edge Function (backend repo `furioke`:
      `supabase/functions/youtube-search/index.ts` + `youtube_search_cache`).
- [x] 2.3 Add a cache-invalidation entry point (`invalidateVideoId`) the iOS
      error bridge calls when a `videoId` is dead (backend repo: `invalidate`
      branch in the Edge Function → `invalidate_youtube_video` RPC; iOS side
      wired in `YouTubeSearchClient.invalidate`).
- [x] 2.4 Document graceful-failure shape so iOS can render "temporarily
      unavailable" — client throws on non-2xx; adapter maps to a
      `transportError` Search renders.

## 3. YouTubePlayerController (WKWebView IFrame bridge)

- [x] 3.1 Create `YouTubePlayerController` owning a `WKWebView` configured with
      `allowsInlineMediaPlayback = true` and
      `mediaTypesRequiringUserActionForPlayback = []`.
- [x] 3.2 Load the IFrame Player HTML (inline template) and expose
      `load(videoId:)`, `play()`, `pause()`, `seek(seconds:)`; current time read
      via the `getCurrentTime()` poll feeding `onTimeUpdate`.
- [x] 3.3 Wire a `WKScriptMessageHandler` for `onReady`, `onStateChange`,
      `onError`; expose them as callbacks to the adapter.
- [x] 3.4 Add the `getCurrentTime()` poll (~400 ms) gated on the playing state,
      cancellable on pause/buffer/teardown.

## 4. YouTubeAdapter (MusicSource)

- [x] 4.1 Create `YouTubeAdapter: MusicSource` for `.youtube`:
      `requiresAccount = false`, `playerSurface = .video`, `getAccount = nil`,
      `connect` resolves `.success`, `getConnection` always `.connected`.
- [x] 4.2 `searchCatalog` / `resolveTracks` call the Edge Function and map to
      provider-neutral `MusicTrack`; `transportError` "unavailable" on failure.
- [x] 4.3 `playTrack` → `controller.load(videoId:)`;
      `control(.play/.pause/.seek)` → controller; `.previous/.next` →
      `.unsupported` (disabled in the transport bar).
- [x] 4.4 Emit `MusicUpdate` from `onStateChange` + each `getCurrentTime()` poll
      (`playbackMode = "youtube-iframe"`); BUFFERING emits a partial update with
      pending id + `isPlaying:false`.
- [x] 4.5 Implement the error bridge: map JS codes (2/5/100/101/150 + 3s
      timeout) to `MusicError` on `playbackError`; clear pending `videoId`; call
      Edge Function cache invalidation for 100/101/150.

## 5. MusicState / teardown

- [x] 5.1 Position flows through the existing `anchor`/`syncPositionTicker` with
      zero `MusicState` change — the adapter emits `positionMs` per poll.
- [x] 5.2 `teardownActive()` → `adapter.disconnect()` → `controller.stop()`
      (stops playback + cancels the poll), so no hidden playing webview is left
      on provider switch / disconnect.
- [x] 5.3 Ad/buffering position handling: on `.buffering` the adapter holds the
      last content position and emits `isPlaying:false`, freezing the active line.

## 6. NowPlaying video surface

- [x] 6.1 Create `YouTubePlayerView` (`UIViewRepresentable`) bound to the shared
      `YouTubePlayerController`.
- [x] 6.2 Mount it in the NowPlaying cover when `music.playerSurface == .video`
      (capability-driven, not `provider == .youtube`); 16:9 region above the
      lyrics via a `videoSurface` slot on `NowPlayingContent`; backdrop otherwise.
- [x] 6.3 No `MPNowPlayingInfoCenter` / `MPRemoteCommandCenter` is registered for
      any source (none exists in the app), so video-backed sources present no
      dead lock-screen control; Spotify/Apple Music unchanged.
- [x] 6.4 "View on YouTube" affordance overlays the player only on a hard
      playback failure (`videoFallback`, gated on the `.video` surface).

## 7. Composition root + Settings

- [x] 7.1 Construct `YouTubePlayerController` at the composition root
      (`FuriokeApp`); inject into `YouTubeAdapter` and the environment for
      `YouTubePlayerView`; register the adapter in the `MusicState` registry.
- [x] 7.2 Settings picker lists YouTube (it's in `availableProviders`); selecting
      it reports `.connected` immediately (account-less), enabling Search at once.

## 8. Verification

- [ ] 8.1 Lyric active-line sync stays aligned across play/pause/seek for a
      YouTube track (manual, with a known-timed song).
- [ ] 8.2 Ad mid-playback: active-line freezes, no desync, resumes after ad.
- [ ] 8.3 Region-locked / removed video: `MusicError` toast + cache
      invalidation + "view on YouTube" fallback; next search returns a live
      video.
- [ ] 8.4 Provider switch YouTube → Spotify → YouTube leaves no leaked webview
      and no leaked update stream.
- [ ] 8.5 Edge Function forced-error path renders "temporarily unavailable";
      Spotify/Apple Music search unaffected.
- [x] 8.6 `openspec validate add-youtube-video-source --strict` passes.
