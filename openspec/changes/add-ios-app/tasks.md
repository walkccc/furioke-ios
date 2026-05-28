## 1. Completed Foundation

- [x] 1.1 Create and configure the iOS project
- [x] 1.2 Add URL scheme, audio background mode, MusicKit, Spotify SDK, and Supabase
- [x] 1.3 Add the iOS design system tokens, primitives, and chrome components
- [x] 1.4 Add the local furigana pipeline
- [x] 1.5 Add Supabase auth with Keychain-backed sessions

## 2. Spotify Walking Skeleton

- [ ] 2.1 Define the basic music types: provider, track, playback update, controls, and errors
- [ ] 2.2 Add `MusicState` and inject it through SwiftUI environment
- [ ] 2.3 Make Spotify the only active provider for this milestone
- [ ] 2.4 Connect Spotify with the iOS SDK
- [ ] 2.5 Show a clear not-installed state when Spotify is missing
- [ ] 2.6 Search Spotify catalog results
- [ ] 2.7 Play and pause Spotify tracks
- [ ] 2.8 Publish current track, position, and playing state from Spotify updates
- [ ] 2.9 Add a root view that switches between signed-out and signed-in states
- [ ] 2.10 Add a minimal signed-in shell with Search and Now Playing
- [ ] 2.11 Build Search with a field and result rows
- [ ] 2.12 Tap a result to start playback
- [ ] 2.13 Fetch lyrics for the playing track
- [ ] 2.14 Run lyrics through the furigana pipeline
- [ ] 2.15 Render annotated lyrics in Now Playing
- [ ] 2.16 Verify sign in, search, playback, and furigana lyrics on device

## 3. Core App Shell

- [ ] 3.1 Harden Spotify connect with explicit states, retry, timeout, and useful errors
- [ ] 3.2 Add Spotify token refresh handling
- [ ] 3.3 Add the full app shell with Library, Search, and Settings
- [ ] 3.4 Make Library the default launch tab
- [ ] 3.5 Add the mini-player above the tab bar
- [ ] 3.6 Add the expanded Now Playing sheet
- [ ] 3.7 Wire mini-player expand and collapse gestures
- [ ] 3.8 Add matched-geometry transitions where appropriate
- [ ] 3.9 Add the one-time mini-player onboarding hint
- [ ] 3.10 Add theme preference: Light, Dark, System
- [ ] 3.11 Add language preference with system default

## 4. Library And Search

- [ ] 4.1 Add provider selection in Settings
- [ ] 4.2 Tear down the old provider cleanly when switching providers
- [ ] 4.3 Build Library from saved songs
- [ ] 4.4 Sync saved songs on launch and Library activation
- [ ] 4.5 Add Library empty state
- [ ] 4.6 Debounce Search input
- [ ] 4.7 Add save state and save action to Search rows
- [ ] 4.8 Add no-provider empty state to Search

## 5. Now Playing

- [ ] 5.1 Add Now Playing source chip
- [ ] 5.2 Add previous, play/pause, and next controls
- [ ] 5.3 Add position scrubber and seek behavior
- [ ] 5.4 Add active lyric highlighting
- [ ] 5.5 Add tap-to-seek on lyric lines when supported
- [ ] 5.6 Add save action in Now Playing
- [ ] 5.7 Add translation toggle and cached translation lookup
- [ ] 5.8 Add album-art backdrop while preserving lyric legibility

## 6. Apple Music

- [ ] 6.1 Request MusicKit authorization
- [ ] 6.2 Search Apple Music catalog
- [ ] 6.3 Play Apple Music tracks in-app
- [ ] 6.4 Publish Apple Music playback updates
- [ ] 6.5 Show a useful no-subscription state
- [ ] 6.6 Verify Search and Now Playing work end to end with Apple Music

## 7. YouTube Metadata

- [ ] 7.1 Search YouTube metadata
- [ ] 7.2 Resolve YouTube video metadata
- [ ] 7.3 Open selected videos in the YouTube app or browser
- [ ] 7.4 Mark native playback controls as unsupported
- [ ] 7.5 Surface useful YouTube playback or embed errors if an embedded player is added

## 8. Offline Cache

- [ ] 8.1 Add SwiftData models for saved songs, lyric bodies, overrides, and translations
- [ ] 8.2 Cache lyric responses with read-through behavior
- [ ] 8.3 Cache translation responses with read-through behavior
- [ ] 8.4 Handle offline hits and misses gracefully
- [ ] 8.5 Add stale checks and cache cleanup on launch
- [ ] 8.6 Purge per-user cached data on sign-out

## 9. Furigana Corrections

- [ ] 9.1 Long-press a kanji token to edit its reading
- [ ] 9.2 Build the inline reading editor
- [ ] 9.3 Re-render lyrics locally after a correction
- [ ] 9.4 Persist corrections locally
- [ ] 9.5 Sync corrections when online
- [ ] 9.6 Queue correction sync while offline

## 10. System Playback Surfaces

- [ ] 10.1 Update Lock Screen and Control Center metadata
- [ ] 10.2 Register remote commands for play, pause, next, previous, and seek
- [ ] 10.3 Keep active lyric text in system playback metadata
- [ ] 10.4 Add CarPlay support
- [ ] 10.5 Verify Lock Screen, Control Center, AirPods, and CarPlay on device

## 11. Accessibility And Polish

- [ ] 11.1 Use only shared motion tokens for animations
- [ ] 11.2 Verify Reduce Transparency behavior
- [ ] 11.3 Verify Reduce Motion behavior
- [ ] 11.4 Audit accessibility labels on interactive controls
- [ ] 11.5 Verify Dynamic Type at large accessibility sizes

## 12. App Store

- [ ] 12.1 Capture App Store screenshots
- [ ] 12.2 Write App Store metadata
- [ ] 12.3 Configure privacy disclosures
- [ ] 12.4 Verify required entitlements
- [ ] 12.5 Submit for review
