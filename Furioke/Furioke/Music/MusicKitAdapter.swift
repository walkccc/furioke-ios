import Combine
import Foundation
import MusicKit

/// The Apple Music `MusicSource` for iOS — fully Apple-native. The
/// `MusicKit` Swift framework authenticates the user's Apple ID directly via
/// `MusicAuthorization.request()`; we never call `/api/apple-music/token` (that
/// server-signed developer-JWT route is web-only). Catalog search and track
/// resolution go through `MusicCatalogSearchRequest` / `MusicCatalogResourceRequest`,
/// and playback runs in-app through `ApplicationMusicPlayer.shared`.
///
/// This vertical covers authorize, search, play/pause/skip/seek,
/// event-driven player-state publishing, and a useful no-subscription state. It
/// drops in behind the `MusicSource` seam without touching feature code.
@MainActor
final class MusicKitAdapter: MusicSource {
  // MARK: MusicSource metadata

  let provider: MusicProvider = .appleMusic
  let requiresAccount = true
  let supportsRepeat = true

  // MARK: Update stream

  /// Vends a *fresh* stream on every access, rebinding `updatesContinuation` to the
  /// new consumer. `MusicState` re-subscribes every time a provider is (re)selected,
  /// and an `AsyncStream` is single-shot: once the iterating task is cancelled — as
  /// `teardownActive()` does on every disconnect / provider switch — that stream is
  /// finished for good. Returning a single stored stream would hand the next
  /// subscriber an already-finished sequence, so nothing (not even `.connected`)
  /// would reach the UI again until the app is killed and relaunched — exactly the
  /// "first connect works, every reconnect fails" symptom. A new stream per access
  /// keeps each connect cycle live; single-active-provider means there's only ever
  /// one consumer, so dropping the previous continuation is safe.
  var updates: AsyncStream<MusicUpdate> {
    AsyncStream { continuation in
      updatesContinuation = continuation
    }
  }

  private var updatesContinuation: AsyncStream<MusicUpdate>.Continuation?

  private var connection: MusicConnection = .disconnected

  /// Subscriptions to the shared player's `state` and `queue` observable objects.
  /// Held only while connected; torn down on `disconnect()` so the update stream
  /// never leaks past an active session.
  private var cancellables: Set<AnyCancellable> = []

  // MARK: Connect (request MusicKit authorization)

  /// Drives Apple-native authorization, then verifies the account can actually
  /// play catalog content. No Furioke server route is in the loop.
  func connect() async -> Result<Void, MusicError> {
    connection = .connecting(provider)

    // The system prompts the user on `.notDetermined`; on subsequent calls it
    // returns the remembered decision without re-prompting.
    let status = await MusicAuthorization.request()
    guard status == .authorized else {
      let error = Self.authorizationError(for: status)
      connection = .failed(provider, error)
      return .failure(error)
    }

    // A useful no-subscription state: an authorized Apple ID without
    // an active subscription cannot stream the catalog, so surface a specific
    // reason rather than letting the first `play()` fail opaquely.
    do {
      let subscription = try await MusicSubscription.current
      guard subscription.canPlayCatalogContent else {
        let error = MusicError.providerRejected(
          "Apple Music needs an active subscription. Subscribe in the Music app to play tracks here."
        )
        connection = .failed(provider, error)
        return .failure(error)
      }
    } catch {
      // The subscription probe itself failing (offline, transient) shouldn't
      // block connect — playback errors still surface per-track downstream.
    }

    connection = .connected(provider)
    startObserving()
    emitCurrent()
    return .success(())
  }

  func disconnect() {
    cancellables.removeAll()
    ApplicationMusicPlayer.shared.stop()
    connection = .disconnected
    emit(track: nil, positionMs: 0, durationMs: 0, isPlaying: false)
  }

  func getConnection() -> MusicConnection {
    connection
  }

  func getAccount() -> MusicAccount? {
    nil
  }

  // MARK: Transport (play in-app)

  func control(_ control: MusicControl) async -> Result<Void, MusicError> {
    let player = ApplicationMusicPlayer.shared
    do {
      switch control {
      case .play: try await player.play()
      case .pause: player.pause()
      case .previous: try await player.skipToPreviousEntry()
      case .next: try await player.skipToNextEntry()
      case let .seek(positionMs):
        player.playbackTime = Double(positionMs) / 1_000
        // Unlike play/pause/skip, setting `playbackTime` mutates neither the
        // observed `state` (playbackStatus) nor `queue`, so no `objectWillChange`
        // fires and the observer never re-emits. Without an explicit emit here
        // `MusicState` keeps interpolating from the pre-seek anchor, leaving the
        // scrubber and active-line highlight stuck until the next state change
        // (e.g. a pause/play). Emit the requested position now so the seek is
        // reflected immediately — matching how Spotify's SDK re-publishes on seek.
        emitCurrent(positionMs: positionMs)
      }
      return .success(())
    } catch {
      return .failure(Self.mapError(error))
    }
  }

  func playTrack(_ track: MusicTrack) async -> Result<Void, MusicError> {
    // Ensure authorization + player-state observation are armed before playing,
    // so a play from a disconnected/restored adapter doesn't leave the UI stale.
    // `connect()` is idempotent (`startObserving` guards on `cancellables.isEmpty`).
    if !connection.isConnected {
      if case let .failure(error) = await connect() { return .failure(error) }
    }
    do {
      let song = try await fetchSong(id: track.providerTrackID)
      let player = ApplicationMusicPlayer.shared
      player.queue = [song]
      try await player.play()
      return .success(())
    } catch {
      return .failure(Self.mapError(error))
    }
  }

  // MARK: Catalog (search; resolve)

  func searchCatalog(query: String, limit: Int) async -> Result<[MusicTrack], MusicError> {
    var request = MusicCatalogSearchRequest(term: query, types: [Song.self])
    request.limit = min(max(limit, 1), 25)
    do {
      let response = try await request.response()
      return .success(response.songs.map(Self.map))
    } catch {
      return .failure(Self.mapError(error))
    }
  }

  func resolveTracks(ids: [String]) async -> Result<[MusicTrack], MusicError> {
    let itemIDs = ids
      .map { MusicItemID(provider.playbackURI(forTrackID: $0)) }
    guard !itemIDs.isEmpty else { return .success([]) }
    let request = MusicCatalogResourceRequest<Song>(matching: \.id, memberOf: itemIDs)
    do {
      let response = try await request.response()
      return .success(response.items.map(Self.map))
    } catch {
      return .failure(Self.mapError(error))
    }
  }

  private func fetchSong(id: String) async throws -> Song {
    let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(id))
    let response = try await request.response()
    guard let song = response.items.first else { throw MusicError.notFound }
    return song
  }

  // MARK: Player-state observation (publish playback updates)

  /// Apple Music playback can be driven from inside Furioke or from elsewhere
  /// (Control Center, another device handed off to this one). Both surface as
  /// `objectWillChange` on the shared player's `state` (play/pause) and `queue`
  /// (track changes), so a single observer covers user-initiated and companion
  /// playback alike.
  private func startObserving() {
    guard cancellables.isEmpty else { return }
    let player = ApplicationMusicPlayer.shared
    player.state.objectWillChange
      .sink { [weak self] in self?.scheduleEmit() }
      .store(in: &cancellables)
    player.queue.objectWillChange
      .sink { [weak self] in self?.scheduleEmit() }
      .store(in: &cancellables)
  }

  /// `objectWillChange` fires *before* the mutation lands, so read the snapshot on
  /// the next main-actor turn once the new value has been applied.
  private func scheduleEmit() {
    Task { @MainActor [weak self] in self?.emitCurrent() }
  }

  /// Yields a `MusicUpdate` snapshotting the shared player. Pass `positionMs` to
  /// override the read-back position right after a seek: `player.playbackTime` can
  /// briefly still report the pre-seek value, so emitting the requested target is
  /// more deterministic for the scrubber and active-line highlight.
  private func emitCurrent(positionMs: Int? = nil) {
    let player = ApplicationMusicPlayer.shared
    let track = Self.track(from: player.queue.currentEntry)
    emit(
      track: track,
      positionMs: positionMs ?? Int(player.playbackTime * 1_000),
      durationMs: track?.durationMs ?? 0,
      isPlaying: player.state.playbackStatus == .playing
    )
  }

  private func emit(track: MusicTrack?, positionMs: Int, durationMs: Int, isPlaying: Bool) {
    let update = MusicUpdate(
      provider: provider,
      connection: connection,
      track: track,
      positionMs: positionMs,
      durationMs: durationMs,
      isPlaying: isPlaying,
      playbackMode: "native-musickit",
      playbackError: nil
    )
    updatesContinuation?.yield(update)
  }

  // MARK: Mapping

  private static func track(from entry: ApplicationMusicPlayer.Queue.Entry?) -> MusicTrack? {
    guard let entry else { return nil }
    if case let .song(song) = entry.item {
      return map(song)
    }
    // Non-song queue entry (rare on this surface): fall back to the entry's own
    // display metadata so the mini-player still renders something coherent.
    return MusicTrack(
      provider: .appleMusic,
      providerTrackID: "",
      uri: "",
      title: entry.title,
      artists: entry.subtitle.map { [$0] } ?? [],
      album: nil,
      durationMs: 0,
      artworkURL: artworkURL(from: entry.artwork)
    )
  }

  private static func map(_ song: Song) -> MusicTrack {
    MusicTrack(
      provider: .appleMusic,
      providerTrackID: song.id.rawValue,
      uri: song.id.rawValue,
      title: song.title,
      artists: [song.artistName],
      album: song.albumTitle,
      durationMs: Int((song.duration ?? 0) * 1_000),
      artworkURL: artworkURL(from: song.artwork)
    )
  }

  /// A renderable URL for a MusicKit `Artwork`, or `nil` when there's genuinely no
  /// art. `Artwork.url(width:height:)` returns `nil` when the requested size is
  /// larger than the asset can serve, and some catalog items report a maximum
  /// smaller than our preferred 600 (a few report 0). Asking flat for 600×600 then
  /// yields `nil` for those songs — and because the Library persists the artwork
  /// URL resolved at save time, the row shows a blank placeholder forever. Clamp
  /// the request to the artwork's reported maximum (when it's known and smaller) so
  /// a present artwork always produces a URL.
  private static func artworkURL(from artwork: Artwork?, preferred: Int = 600) -> URL? {
    guard let artwork else { return nil }
    let maxDimension = [artwork.maximumWidth, artwork.maximumHeight]
      .filter { $0 > 0 }
      .min()
    let size = maxDimension.map { min(preferred, $0) } ?? preferred
    return artwork.url(width: size, height: size)
  }

  private static func authorizationError(for status: MusicAuthorization.Status) -> MusicError {
    switch status {
    // `.denied` covers both an immediate "Don't Allow" tap and a decision
    // remembered from a previous launch — in the latter case iOS shows no prompt
    // at all, so a silent no-op reads as "Connect does nothing". Surface an
    // actionable message pointing to Settings rather than failing silently.
    case .denied:
      .providerRejected(
        "Apple Music access is off. Enable it in Settings › Furioke to play tracks here."
      )
    case .restricted:
      .providerRejected("Apple Music access is restricted on this device.")
    default:
      .providerRejected("Allow Apple Music access in Settings to play tracks here.")
    }
  }

  private static func mapError(_ error: any Error) -> MusicError {
    if let musicError = error as? MusicError { return musicError }
    if error is CancellationError { return .cancelled }
    return .providerRejected(error.localizedDescription)
  }
}
