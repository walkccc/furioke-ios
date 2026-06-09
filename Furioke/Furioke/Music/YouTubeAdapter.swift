import Foundation

/// The YouTube `MusicSource` — an account-less, in-app **video** source. Search
/// and resolve go through the InnerTube-backed `youtube-search` Supabase Edge
/// Function (`YouTubeSearchClient`); playback drives the YouTube IFrame Player via
/// the injected `YouTubePlayerController`. Framed as a YouTube karaoke / video
/// source, never as "YouTube Music".
///
/// There is no auth: `connect` resolves immediately and `getConnection` always
/// reports connected, so selecting YouTube in Settings is instant and Search is
/// enabled at once. Position is fed from the controller's `getCurrentTime()` poll
/// into the existing `MusicState` interpolation — no new position path.
@MainActor
final class YouTubeAdapter: MusicSource {
  let provider: MusicProvider = .youtube
  let requiresAccount = false
  // IFrame loop is not wired in v1; the transport bar's repeat affordance stays
  // disabled like any unsupported control.
  let supportsRepeat = false
  let supportsPlaybackRate = true
  let playerSurface: MusicPlayerSurface = .video

  /// Vends a fresh stream on every access (mirrors `MusicKitAdapter`): `MusicState`
  /// re-subscribes on every provider (re)selection and an `AsyncStream` is
  /// single-shot, so a stored stream would hand the next subscriber a finished
  /// sequence. Single-active-provider means there's only ever one consumer.
  var updates: AsyncStream<MusicUpdate> {
    AsyncStream { continuation in
      updatesContinuation = continuation
    }
  }

  private var updatesContinuation: AsyncStream<MusicUpdate>.Continuation?

  private let controller: YouTubePlayerController
  private let search = YouTubeSearchClient()

  private var currentTrack: MusicTrack?
  private var positionMs = 0
  private var durationMs = 0
  private var isPlaying = false
  private var playbackRate = MusicPlaybackRate.default

  /// The id of a video whose playback we're waiting to confirm (`.playing` not yet
  /// seen). Cleared on `.playing`, on error, or on the 3s start-timeout. Drives the
  /// "forever-buffering stall" detection.
  private var pendingVideoId: String?
  private var startTimeoutTask: Task<Void, Never>?

  /// Remembers which query produced each video id, so a dead id can invalidate the
  /// exact cache entry that surfaced it.
  private var queryByVideoId: [String: String] = [:]

  init(controller: YouTubePlayerController) {
    self.controller = controller
    wireController()
  }

  // MARK: Connection (account-less)

  func getConnection() -> MusicConnection {
    .connected(provider)
  }

  func getAccount() -> MusicAccount? {
    nil
  }

  func connect() -> Result<Void, MusicError> {
    emitCurrent()
    return .success(())
  }

  func disconnect() {
    controller.stop()
    startTimeoutTask?.cancel()
    startTimeoutTask = nil
    pendingVideoId = nil
    currentTrack = nil
    positionMs = 0
    durationMs = 0
    isPlaying = false
    emit(track: nil, positionMs: 0, durationMs: 0, isPlaying: false)
  }

  // MARK: Transport

  func playTrack(_ track: MusicTrack) -> Result<Void, MusicError> {
    currentTrack = track
    pendingVideoId = track.providerTrackID
    positionMs = 0
    durationMs = track.durationMs
    isPlaying = false
    // A fresh track always starts at normal speed — YouTube otherwise carries the
    // previous video's rate across a load.
    playbackRate = MusicPlaybackRate.default
    controller.load(videoId: track.providerTrackID)
    controller.setPlaybackRate(MusicPlaybackRate.default)
    armStartTimeout(for: track.providerTrackID)
    return .success(())
  }

  func control(_ control: MusicControl) -> Result<Void, MusicError> {
    switch control {
    case .play:
      controller.play()
    case .pause:
      controller.pause()
    case let .seek(positionMs):
      controller.seek(seconds: Double(positionMs) / 1_000)
      self.positionMs = positionMs
      emitCurrent()
    case let .setPlaybackRate(rate):
      playbackRate = rate
      controller.setPlaybackRate(rate)
      emitCurrent()
    case .previous, .next:
      // No queue concept for a single embedded video.
      return .failure(.unsupported)
    }
    return .success(())
  }

  // MARK: Catalog (InnerTube via Edge Function)

  func searchCatalog(query: String, limit: Int) async -> Result<[MusicTrack], MusicError> {
    do {
      let results = try await search.search(query: query, limit: limit)
      return .success(results.map { result in
        queryByVideoId[result.videoId] = query
        return Self.map(result)
      })
    } catch {
      // Graceful degradation: the InnerTube proxy may break until hotfixed. Surface
      // a clear message (Search renders it) rather than crashing or hanging.
      return .failure(.transportError("YouTube search is temporarily unavailable."))
    }
  }

  func resolveTracks(ids: [String]) async -> Result<[MusicTrack], MusicError> {
    do {
      let results = try await search.resolve(videoIds: ids)
      return .success(results.map(Self.map))
    } catch {
      // A failed resolve shouldn't blank the Library; the rows still carry their
      // stored title/artist for display.
      return .success([])
    }
  }

  // MARK: Controller wiring

  private func wireController() {
    controller.onReady = { [weak self] in self?.emitCurrent() }
    controller.onStateChange = { [weak self] state in self?.handle(state: state) }
    controller.onError = { [weak self] code in self?.handle(errorCode: code) }
    controller.onTimeUpdate = { [weak self] current, duration in
      guard let self else { return }
      positionMs = Int(current * 1_000)
      if duration > 0 { durationMs = Int(duration * 1_000) }
      emitCurrent()
    }
  }

  private func handle(state: YouTubePlayerState) {
    switch state {
    case .playing:
      // Playback confirmed: cancel the stall timeout and start the position poll.
      startTimeoutTask?.cancel()
      startTimeoutTask = nil
      pendingVideoId = nil
      isPlaying = true
      controller.startPolling()
      emitCurrent()
    case .paused, .ended:
      isPlaying = false
      controller.stopPolling()
      emitCurrent()
    case .buffering:
      // Ad / buffering: hold the last content position so the active-line highlight
      // freezes instead of jumping to the ad's timeline. Emit a partial snapshot
      // (pending id + isPlaying:false) rather than nil so the surface shows a
      // loading state instead of a frozen blank.
      isPlaying = false
      controller.stopPolling()
      emit(
        track: currentTrack,
        positionMs: positionMs,
        durationMs: durationMs,
        isPlaying: false
      )
    case .unstarted, .cued:
      break
    }
  }

  private func handle(errorCode code: Int) {
    let error: MusicError = switch code {
    case 2: .unplayable
    case 5: .embedDisabled
    case 100: .notFound
    case 101, 150: .regionLocked
    default: .playbackDidNotStart
    }

    let deadVideoId = pendingVideoId ?? currentTrack?.providerTrackID
    startTimeoutTask?.cancel()
    startTimeoutTask = nil
    pendingVideoId = nil
    isPlaying = false
    controller.stopPolling()
    emit(
      track: currentTrack,
      positionMs: positionMs,
      durationMs: durationMs,
      isPlaying: false,
      error: error
    )

    // Any IFrame error means this exact video failed to play in-embed (removed,
    // region-locked, embed-disabled, or a player error) — drop the cache entry
    // that surfaced it so the next identical search re-resolves a live video
    // rather than handing back the dead id.
    if let videoId = deadVideoId { markVideoDead(videoId) }
  }

  /// Detect a forever-buffering stall: if no `.playing` arrives within 3s of a
  /// load, surface `playbackDidNotStart` and clear the pending id so the next play
  /// isn't blocked by stale state.
  private func armStartTimeout(for videoId: String) {
    startTimeoutTask?.cancel()
    startTimeoutTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(3))
      guard let self, !Task.isCancelled, pendingVideoId == videoId else { return }
      pendingVideoId = nil
      isPlaying = false
      emit(
        track: currentTrack,
        positionMs: 0,
        durationMs: durationMs,
        isPlaying: false,
        error: .playbackDidNotStart
      )
      // A silent stall is the symptom of an unembeddable / age-restricted /
      // region-locked straggler whose in-player overlay (e.g. "Error code:
      // 152") never reaches `onError`. Treat it like a dead id so the next
      // identical search re-resolves instead of re-serving the same broken one.
      markVideoDead(videoId)
    }
  }

  /// Drop a now-dead video id locally and ask the Edge Function to invalidate the
  /// cache entry that produced it, so the next identical search re-resolves a live
  /// video. Best-effort: `search.invalidate` swallows its own failures.
  private func markVideoDead(_ videoId: String) {
    queryByVideoId[videoId] = nil
    Task { await search.invalidate(videoId: videoId) }
  }

  // MARK: Emitting

  private func emitCurrent() {
    emit(track: currentTrack, positionMs: positionMs, durationMs: durationMs, isPlaying: isPlaying)
  }

  private func emit(
    track: MusicTrack?,
    positionMs: Int,
    durationMs: Int,
    isPlaying: Bool,
    error: MusicError? = nil
  ) {
    let update = MusicUpdate(
      provider: provider,
      connection: .connected(provider),
      track: track,
      positionMs: positionMs,
      durationMs: durationMs,
      isPlaying: isPlaying,
      playbackMode: "youtube-iframe",
      playbackError: error,
      playbackRate: playbackRate
    )
    updatesContinuation?.yield(update)
  }

  // MARK: Mapping

  private static func map(_ result: YouTubeSearchClient.Result) -> MusicTrack {
    MusicTrack(
      provider: .youtube,
      providerTrackID: result.videoId,
      uri: MusicProvider.youtube.playbackURI(forTrackID: result.videoId),
      title: result.title,
      artists: result.artists,
      album: nil,
      durationMs: result.durationMs,
      artworkURL: result.thumbnailUrl.flatMap(URL.init(string:))
    )
  }
}
