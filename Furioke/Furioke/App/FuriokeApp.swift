import SwiftData
import SwiftUI

@main
struct FuriokeApp: App {
  // Root-owned observables, injected into the environment. Both provider adapters
  // are registered with `MusicState`, which activates the one the user selected
  // (persisted) and leaves the rest idle. The Spotify adapter is
  // held here too so its deep-link callback can route to it regardless of which
  // provider is active.
  @State private var auth: AuthService
  @State private var spotify: SpotifyAdapter
  @State private var music: MusicState
  @State private var nowPlaying: NowPlayingState
  @State private var preferences: PreferencesState
  @State private var network: NetworkMonitor
  @State private var cache: OfflineCache
  @State private var library: LibraryState
  @State private var overrides: ReadingOverridesState

  /// Drives the Spotify App Remote connect lifecycle: the post-auth-callback connect
  /// must wait for `.active`, and a session dropped while backgrounded is revived on
  /// return to foreground (SpotifyAdapter.setForegroundActive).
  @Environment(\.scenePhase) private var scenePhase

  init() {
    let auth = AuthService()
    let spotify = SpotifyAdapter()
    let appleMusic = MusicKitAdapter()
    let music = MusicState(adapters: [spotify, appleMusic])
    let network = NetworkMonitor()
    let cache = OfflineCache()
    let preferences = PreferencesState()
    let lyrics = LyricsService(auth: auth)
    let lyricRepository = LyricRepository(service: lyrics, cache: cache, network: network)
    let translationRepository = TranslationRepository(
      service: TranslationService(auth: auth),
      cache: cache,
      network: network
    )
    let corrections = ReadingCorrectionsService(auth: auth)
    let nowPlaying = NowPlayingState(
      music: music,
      repository: lyricRepository,
      translation: translationRepository,
      preferences: preferences,
      cache: cache,
      auth: auth,
      corrections: corrections,
      network: network
    )
    let overrides = ReadingOverridesState(
      cache: cache,
      corrections: corrections,
      auth: auth,
      network: network
    )
    let library = LibraryState(
      cache: cache,
      service: SavedSongsService(auth: auth),
      network: network
    )

    // Purge every per-user cache entity on explicit sign-out. Auth must
    // not import the cache, so the composition root wires the teardown here.
    auth.onSignOutCleanup = { [cache] in cache.purgeAll() }

    _auth = State(initialValue: auth)
    _spotify = State(initialValue: spotify)
    _music = State(initialValue: music)
    _nowPlaying = State(initialValue: nowPlaying)
    _preferences = State(initialValue: preferences)
    _network = State(initialValue: network)
    _cache = State(initialValue: cache)
    _library = State(initialValue: library)
    _overrides = State(initialValue: overrides)
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(auth)
        .environment(music)
        .environment(nowPlaying)
        .environment(preferences)
        .environment(network)
        .environment(library)
        .environment(overrides)
        // The offline cache's SwiftData container backs `@Query` in the Library
        // tab and `modelContext` writes elsewhere.
        .modelContainer(cache.container)
        // Appearance + language overrides apply above the sign-in gate so they
        // hold on both the sign-in surface and the AppShell, and on every launch.
        .preferredColorScheme(preferences.theme.colorScheme)
        .environment(\.locale, preferences.resolvedLocale ?? .autoupdatingCurrent)
        // Spotify deep-link callback (furioke://spotify-callback) → SDK session.
        .onOpenURL { spotify.handleOpenURL($0) }
        // Connect App Remote only once the scene is active (the callback can arrive
        // earlier), and revive a backgrounded-and-dropped session on return.
        .onChange(of: scenePhase) { _, phase in
          spotify.setForegroundActive(phase == .active)
        }
        // Evict cache entries past the 90-day retention bound, off the launch
        // critical path.
        .task { cache.runJanitor() }
        // Warm the kuromoji tokenizer in the background so the first song's
        // furigana doesn't pay the multi-second cold dictionary build on the
        // lyric render path. Lyrics still show instantly regardless; this just
        // shortens how long the "adding furigana" indicator is up.
        .task { try? await KuromojiBridge.shared.preload() }
    }
  }
}
