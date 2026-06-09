import Foundation
import Observation

/// The provider-neutral playback observable. Feature code (Search, NowPlaying,
/// Settings) reads playback state and issues control here — never against
/// `SPTAppRemote` or any other SDK type. It sources
/// from the active `MusicSource` adapter's `updates` stream.
///
/// The user selects exactly one active provider at a time. The selection is
/// restored on launch from `UserDefaults` — without auto-connecting — and
/// switching providers tears the previous adapter down exactly once before the
/// next one activates.
@Observable
@MainActor
final class MusicState {
  private(set) var connection: MusicConnection = .disconnected
  private(set) var currentTrack: MusicTrack?
  private(set) var positionMs = 0
  private(set) var durationMs = 0
  private(set) var isPlaying = false
  private(set) var playbackMode: String?
  /// The active source's current playback rate (1 = normal). Scales position
  /// interpolation so the scrubber and active-line highlight track the audio at
  /// non-1× rates, and drives the speed control's selected option.
  private(set) var playbackRate = MusicPlaybackRate.default

  /// The most recent mid-session failure carried on a `MusicUpdate`, for feature
  /// views to render a toast against.
  private(set) var lastPlaybackError: MusicError?

  /// Who initiated the current playback — set by `NowPlayingState.play(track:)`
  /// for user-initiated playback; the observed (companion) case lands in a later
  /// change.
  var source: PlaybackSource?

  /// Every adapter the app knows how to drive, keyed by provider. Built once at the
  /// composition root; only the active one is observed and connected, the rest stay
  /// idle until selected.
  @ObservationIgnored private let registry: [MusicProvider: any MusicSource]
  @ObservationIgnored private let defaults: UserDefaults

  /// The active adapter, or `nil` when no provider is selected — a fresh launch with
  /// nothing stored, or after the user disconnects. Feature code reads
  /// `activeProvider`, not this directly.
  private(set) var adapter: (any MusicSource)?

  @ObservationIgnored private var observeTask: Task<Void, Never>?

  // Position interpolation. The Spotify SDK only emits `playerStateDidChange` on
  // discrete events (play / pause / track / seek), never per tick — so between
  // emissions we project `positionMs` forward from the last authoritative value
  // while playing. This is what makes the scrubber and the active-line highlight
  // advance smoothly during playback rather than freezing until the next event.
  @ObservationIgnored private var positionTicker: Task<Void, Never>?
  @ObservationIgnored private var anchorPositionMs = 0
  @ObservationIgnored private var anchorAt = Date()

  /// Auto-clears `lastPlaybackError` a few seconds after it's surfaced, so a
  /// transient playback toast doesn't linger after the user has recovered.
  @ObservationIgnored private var errorResetTask: Task<Void, Never>?

  private enum Key {
    static let activeProvider = "furioke.music.activeProvider"
  }

  init(adapters: [any MusicSource], defaults: UserDefaults = .standard) {
    self.defaults = defaults
    registry = Dictionary(uniqueKeysWithValues: adapters.map { ($0.provider, $0) })
    // Restore the previously-active provider, but do NOT connect it — the app must
    // not auto-connect a provider in the background. The user reconnects
    // explicitly from Settings.
    if let restored = defaults.string(forKey: Key.activeProvider)
      .flatMap(MusicProvider.init(rawValue:)),
      let adapter = registry[restored]
    {
      attach(adapter)
    }
  }

  deinit {
    observeTask?.cancel()
    positionTicker?.cancel()
    errorResetTask?.cancel()
  }

  /// The selected provider, or `nil` when none is active.
  var activeProvider: MusicProvider? {
    adapter?.provider
  }

  /// The active source's required player surface, or `.none` when nothing is
  /// active. Feature/view code reads this to decide whether to mount a video
  /// player — it never branches on a specific provider, and `MusicState` itself
  /// stays headless (it never references a `WKWebView`).
  var playerSurface: MusicPlayerSurface {
    adapter?.playerSurface ?? .none
  }

  /// Whether the active source can change playback rate — drives whether the
  /// NowPlaying surface offers the speed control. False when no provider is active.
  var supportsPlaybackRate: Bool {
    adapter?.supportsPlaybackRate ?? false
  }

  /// Providers offered in the Settings picker — only those with a registered
  /// adapter.
  var availableProviders: [MusicProvider] {
    MusicProvider.allCases.filter { registry[$0] != nil }
  }

  var isConnected: Bool {
    connection.isConnected
  }

  var hasLoadedTrack: Bool {
    currentTrack != nil
  }

  // MARK: Provider selection

  /// Select — or switch to — a provider. The previous adapter is torn down exactly
  /// once before the new one activates; the new provider is left disconnected so
  /// the user connects it explicitly. A no-op when the provider is already active
  /// or unregistered.
  func select(_ provider: MusicProvider) async {
    guard provider != adapter?.provider, let next = registry[provider] else { return }
    await teardownActive()
    defaults.set(provider.rawValue, forKey: Key.activeProvider)
    attach(next)
  }

  /// Tear down the active adapter and the update subscription exactly once, then
  /// clear all playback state so the next provider starts clean.
  private func teardownActive() async {
    observeTask?.cancel()
    observeTask = nil
    positionTicker?.cancel()
    positionTicker = nil
    await adapter?.disconnect()
    resetPlaybackState()
  }

  /// Make `adapter` the active source and start observing its update stream. Mirrors
  /// the adapter's current connection (a freshly-selected adapter is disconnected).
  private func attach(_ adapter: any MusicSource) {
    self.adapter = adapter
    connection = adapter.getConnection()
    observe()
  }

  private func resetPlaybackState() {
    connection = .disconnected
    currentTrack = nil
    source = nil
    positionMs = 0
    durationMs = 0
    isPlaying = false
    playbackMode = nil
    playbackRate = MusicPlaybackRate.default
    lastPlaybackError = nil
  }

  private func observe() {
    guard let adapter else { return }
    observeTask = Task { [weak self, updates = adapter.updates] in
      for await update in updates {
        guard let self else { break }
        apply(update)
      }
    }
  }

  private func apply(_ update: MusicUpdate) {
    connection = update.connection
    if let track = update.track {
      currentTrack = track
      // Mark externally-driven playback as observed (companion) so the UI has a
      // `source` to read — the artwork fallback and source chip work the same in
      // both flows. A `.userInitiated` source for the *same* track is preserved:
      // it carries the search/library artwork the SDK echo lacks. A different id
      // means the user skipped or playback advanced outside the app.
      if source?.track.id != track.id {
        source = .observed(track)
      }
    }
    durationMs = update.durationMs
    isPlaying = update.isPlaying
    playbackMode = update.playbackMode
    playbackRate = update.playbackRate
    if let error = update.playbackError { setPlaybackError(error) }
    // Re-anchor interpolation to this authoritative position, then (re)arm the
    // ticker for the current play/pause state.
    anchor(positionMs: update.positionMs)
    syncPositionTicker()
  }

  private func anchor(positionMs ms: Int) {
    positionMs = ms
    anchorPositionMs = ms
    anchorAt = Date()
  }

  private func syncPositionTicker() {
    positionTicker?.cancel()
    guard isPlaying else { return }
    positionTicker = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(250))
        guard let self, isPlaying else { return }
        // Scale elapsed wall-clock by the playback rate so the projected position
        // advances at the audio's true rate (e.g. half as fast at 0.5×).
        let elapsed = Date().timeIntervalSince(anchorAt) * 1_000 * playbackRate
        let projected = anchorPositionMs + Int(elapsed)
        positionMs = durationMs > 0 ? min(projected, durationMs) : projected
      }
    }
  }

  // MARK: Commands delegated to the active adapter

  /// Show a user-picked track on the mini-player and Now Playing surface
  /// immediately — before the adapter echoes it back. The display binds to
  /// `currentTrack`, and the SDK echo can lag the tap by a full connect/play
  /// round-trip (for a disconnected provider it may not arrive for seconds), so
  /// without this the title/artist/artwork stay blank after the tap. The
  /// authoritative echo for the same track id later supersedes this; the
  /// `.userInitiated` source is preserved so the richer library artwork survives.
  func showUserInitiated(_ track: MusicTrack) {
    source = .userInitiated(track)
    currentTrack = track
    durationMs = track.durationMs
    isPlaying = true
    // A freshly user-started track always begins at normal speed.
    playbackRate = MusicPlaybackRate.default
    anchor(positionMs: 0)
    syncPositionTicker()
  }

  func connect() async -> Result<Void, MusicError> {
    guard let adapter else { return .failure(.unsupported) }
    return await adapter.connect()
  }

  /// Disconnect and clear the active provider entirely — UserDefaults reflects no
  /// active provider until the user picks one again.
  func disconnect() async {
    await teardownActive()
    adapter = nil
    defaults.removeObject(forKey: Key.activeProvider)
  }

  func control(_ control: MusicControl) async -> Result<Void, MusicError> {
    guard let adapter else { return .failure(.unsupported) }
    // Self-heal: a disconnected provider can't honor a transport command. On an
    // explicit resume of the still-shown track, reconnect-and-play in one step
    // (each adapter's `playTrack` re-establishes the session) rather than no-op.
    // User-action only — never a background auto-connect.
    let result: Result<Void, MusicError> = if case .play = control, !isConnected,
                                              let track = currentTrack
    {
      await adapter.playTrack(track)
    } else {
      await adapter.control(control)
    }
    reconcile(control, result)
    return result
  }

  func playTrack(_ track: MusicTrack) async -> Result<Void, MusicError> {
    guard let adapter else { return .failure(.unsupported) }
    let result = await adapter.playTrack(track)
    // The optimistic `showUserInitiated` set `isPlaying = true` before the adapter
    // ran; if it failed (a Spotify reconnect that never completed, a user cancel),
    // no SDK echo follows to undo that — so clear it here, or the button is stuck
    // showing "pause" over a track that isn't playing.
    if case let .failure(error) = result {
      setPlaybackError(error)
      isPlaying = false
      syncPositionTicker()
    }
    return result
  }

  /// Reconcile the optimistic UI state against a transport command's outcome. The
  /// SDK echo is authoritative when it arrives, but a failed or unhonored command
  /// often emits no echo at all (a failed Spotify reconnect, a provider whose
  /// socket dropped on backgrounding) — so without this the play/pause glyph can
  /// lie: stuck on "pause" while nothing plays, which then sends a no-op `.pause`
  /// on the next tap instead of letting the `.play` self-heal fire. Dead button.
  private func reconcile(_ control: MusicControl, _ result: Result<Void, MusicError>) {
    switch result {
    case .success:
      switch control {
      case .play: isPlaying = true
        clearPlaybackError()
      case .pause: isPlaying = false
      default: break
      }
      syncPositionTicker()
    case let .failure(error):
      setPlaybackError(error)
      // A transport command we couldn't honor means we aren't actually playing —
      // clear the optimistic flag so the button reverts to "play" and the next tap
      // self-heals (reconnect-and-play) rather than sending a no-op pause.
      if !isConnected || error == .needsReconnect {
        isPlaying = false
        syncPositionTicker()
      }
    }
  }

  /// Surface a playback failure to feature views (a toast against
  /// `lastPlaybackError`) and arm its auto-dismiss. Errors whose `userMessage` is
  /// nil (user-cancelled, silent renew) set state but render nothing.
  private func setPlaybackError(_ error: MusicError) {
    lastPlaybackError = error
    errorResetTask?.cancel()
    errorResetTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(4))
      guard let self, !Task.isCancelled else { return }
      lastPlaybackError = nil
    }
  }

  func clearPlaybackError() {
    errorResetTask?.cancel()
    lastPlaybackError = nil
  }

  func search(_ query: String,
              limit: Int = MusicSearch.defaultLimit) async -> Result<[MusicTrack], MusicError>
  {
    guard let adapter else { return .success([]) }
    return await adapter.searchCatalog(query: query, limit: limit)
  }
}
