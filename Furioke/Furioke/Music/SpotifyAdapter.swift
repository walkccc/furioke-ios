import Foundation
import SpotifyiOS
import UIKit

/// The Spotify `MusicSource` for iOS — fully client-side. The
/// Spotify iOS SDK (`SPTAppRemote`) drives the deep-link auth flow via
/// `authorizeAndPlayURI`, which wakes the Spotify app *and* primes a playback
/// session so App Remote can attach reliably; we never call a Furioke server
/// route for token brokering. Catalog search and track resolution go direct to
/// `api.spotify.com` with the access token parsed from the auth callback.
///
/// This is the happy path: connect, search, play/pause/skip/seek,
/// and event-driven player-state publishing. The hardening pass adds the
/// 1.5s foreground grace window, the 8s handshake timeout, and 401-renew retry.
@MainActor
final class SpotifyAdapter: NSObject, MusicSource {
  // MARK: MusicSource metadata

  let provider: MusicProvider = .spotify
  let requiresAccount = true
  let supportsRepeat = true
  /// Spotify's iOS SDK exposes no playback-rate control.
  let supportsPlaybackRate = false

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

  // MARK: SDK objects

  private let configuration: SPTConfiguration
  private let appRemote: SPTAppRemote

  /// The current access token, parsed from the authorize callback. App Remote
  /// uses it for the transport; the Web API search/resolve calls reuse it
  /// directly (the App-Remote authorize flow has no `SPTSessionManager.session`).
  private var accessToken: String?

  /// Album artwork resolved for SDK-published tracks, keyed by bare track id. The
  /// App Remote player state carries no artwork URL (only an image identifier for
  /// the SDK image API), so we resolve it once via the Web API and cache it.
  private var artworkCache: [String: URL] = [:]
  private var artworkInFlight: Set<String> = []
  /// The most recent player snapshot, kept so a late artwork resolution can
  /// re-emit the current track with its now-known artwork.
  private var lastSnapshot: PlayerSnapshot?

  // MARK: Update stream

  private var updatesContinuation: AsyncStream<MusicUpdate>.Continuation?

  private var connection: MusicConnection = .disconnected

  // MARK: Connect state machine

  //
  // The connect handshake is resolved by this single-shot continuation, fed only
  // by SDK delegate events — never by `withCheckedContinuation`, so a double
  // delegate callback can't resume twice.

  private enum ConnectPhase { case idle, linking, connected, failed }
  private var connectPhase: ConnectPhase = .idle
  private var connectContinuation: AsyncStream<Result<Void, MusicError>>.Continuation?

  /// The plain Connect button still has to `authorizeAndPlayURI` to prime a session
  /// (App Remote can't attach to an idle Spotify), but the empty URI resumes the
  /// user's last context — i.e. it starts playback. Connecting shouldn't start music
  /// on its own, so this flag tells `appRemoteDidEstablishConnection` to pause that
  /// primed playback the instant the transport attaches. A connect carrying a real
  /// track URI (auto-connect-then-play) leaves it false, and so does the
  /// background-revive reconnect, which should resume whatever was playing.
  private var pauseOnConnect = false

  // Foreground gating. `SPTAppRemote.connect()` only succeeds once the host scene
  // is `.active`, but the auth deep link (`onOpenURL`) can arrive while the scene
  // is still *transitioning* to foreground — connecting then lands in
  // `didFailConnectionAttempt`. So we record the token, mark a connect pending, and
  // let `setForegroundActive(true)` drive the actual `connect()`. The same hook
  // revives a session App Remote silently dropped while backgrounded.
  private var isForegroundActive = false
  private var pendingConnect = false

  override init() {
    let config = SPTConfiguration(
      clientID: SpotifyConfig.clientID,
      redirectURL: SpotifyConfig.redirectURL
    )
    configuration = config
    appRemote = SPTAppRemote(configuration: config, logLevel: .error)

    super.init()
    appRemote.delegate = self
  }

  // MARK: Connect

  func connect() async -> Result<Void, MusicError> {
    // The plain Connect button just links the account; it does not start playback.
    await connect(playing: "")
  }

  /// The shared connect handshake. `uri` is the track to start once Spotify
  /// authorizes: an explicit track URI both primes the session *and* starts the
  /// tapped song — so auto-connect-then-play is a single app switch. The empty
  /// string (the Connect button) still primes a session so App Remote can attach,
  /// but `pauseOnConnect` pauses it on attach so connecting alone never plays.
  private func connect(playing uri: String) async -> Result<Void, MusicError> {
    // Short-circuit the genuine "not installed" case before touching SDK
    // transport, so it is never masked by a transport error.
    guard let scheme = URL(string: "spotify://"), UIApplication.shared.canOpenURL(scheme) else {
      connection = .failed(provider, .notInstalled)
      return .failure(.notInstalled)
    }
    guard connectPhase != .linking else { return .failure(.cancelled) }

    connectPhase = .linking
    connection = .connecting(provider)
    // An empty URI is the plain Connect button: prime the session to attach, then
    // pause it on connect so linking the account never starts music on its own.
    pauseOnConnect = uri.isEmpty

    let (stream, continuation) = AsyncStream<Result<Void, MusicError>>.makeStream()
    connectContinuation = continuation
    // `authorizeAndPlayURI` app-switches to Spotify, authorizes, and primes a
    // playback session, then deep-links back to `furioke://spotify-callback`.
    // Passing a track URI starts that song; the empty URI resumes the user's last
    // context — either way it guarantees an active session so the subsequent App
    // Remote connect attaches instead of failing against an idle Spotify. The
    // not-installed case is already short-circuited above, so the app is present.
    await appRemote.authorizeAndPlayURI(uri)

    for await result in stream {
      return result
    }
    return .failure(.cancelled)
  }

  /// The only path that resolves a connect attempt. Guarded by `connectPhase` so
  /// a repeated delegate event after the first resolution is a no-op.
  private func finishConnect(_ result: Result<Void, MusicError>) {
    guard connectPhase == .linking else { return }
    if case .success = result {
      connectPhase = .connected
    } else {
      connectPhase = .failed
    }
    connectContinuation?.yield(result)
    connectContinuation?.finish()
    connectContinuation = nil
  }

  func disconnect() {
    appRemote.disconnect()
    connectPhase = .idle
    pendingConnect = false
    pauseOnConnect = false
    connection = .disconnected
    emit(track: nil, positionMs: 0, durationMs: 0, isPlaying: false)
  }

  /// Routed from the app's `onOpenURL`. Parses the access token (or error) out of
  /// the `furioke://spotify-callback` redirect. On success we hand the token to
  /// App Remote and connect its transport; the `appRemote` delegate then resolves
  /// the pending connect attempt. A token-less callback means the user dismissed
  /// the Spotify auth prompt (or Spotify returned an error), so we resolve here.
  func handleOpenURL(_ url: URL) {
    let params = appRemote.authorizationParameters(from: url)
    if let token = params?[SPTAppRemoteAccessTokenKey] {
      accessToken = token
      appRemote.connectionParameters.accessToken = token
      // Defer the actual `connect()` to scene-active. The callback frequently lands
      // before the scene reaches `.active`; connecting now would fail the handshake
      // intermittently (the "redirect back but still stale" case). `connectIfActive`
      // fires immediately when already active, otherwise `setForegroundActive` does.
      pendingConnect = true
      connectIfActive()
    } else {
      let failed = params?[SPTAppRemoteErrorDescriptionKey] != nil
      let reason: MusicError = failed
        ? .transportError("Couldn't connect to Spotify. Open the Spotify app and try again.")
        : .userCancelled
      connection = .failed(provider, reason)
      finishConnect(.failure(reason))
    }
  }

  /// Routed from the app's `scenePhase` observer. Drives the deferred post-callback
  /// connect once the scene is genuinely active, and — for an already-established
  /// session that App Remote dropped while the app was backgrounded (the socket
  /// closes on background and is never auto-revived) — reconnects it so transport
  /// keeps working on return. Reconnect only ever revives a session *this run*
  /// already authorized (guarded on `accessToken`); it is never a cold auto-connect.
  func setForegroundActive(_ active: Bool) {
    isForegroundActive = active
    guard active else { return }
    if pendingConnect {
      connectIfActive()
    } else if accessToken != nil, connectPhase == .connected, !appRemote.isConnected {
      connection = .connecting(provider)
      appRemote.connect()
    }
  }

  /// Connect now if we're both holding a token and foreground-active; otherwise the
  /// request stays pending until `setForegroundActive(true)` retries it.
  private func connectIfActive() {
    guard isForegroundActive, accessToken != nil else { return }
    pendingConnect = false
    appRemote.connect()
  }

  func getConnection() -> MusicConnection {
    connection
  }

  func getAccount() -> MusicAccount? {
    nil
  }

  // MARK: Transport

  func control(_ control: MusicControl) async -> Result<Void, MusicError> {
    if case .setPlaybackRate = control { return .failure(.unsupported) }
    guard let player = appRemote.playerAPI else { return .failure(.needsReconnect) }
    return await withCheckedContinuation { continuation in
      let handler: (Any?, (any Error)?) -> Void = { _, error in
        if let error {
          continuation.resume(returning: .failure(.providerRejected(error.localizedDescription)))
        } else {
          continuation.resume(returning: .success(()))
        }
      }
      switch control {
      case .play: player.resume(handler)
      case .pause: player.pause(handler)
      case .previous: player.skip(toPrevious: handler)
      case .next: player.skip(toNext: handler)
      case let .seek(positionMs): player.seek(toPosition: positionMs, callback: handler)
      // Rejected before reaching the player above; handled here only for switch
      // exhaustiveness.
      case .setPlaybackRate: continuation.resume(returning: .failure(.unsupported))
      }
    }
  }

  func playTrack(_ track: MusicTrack) async -> Result<Void, MusicError> {
    // Auto-connect on demand. When App Remote isn't attached yet — the user tapped
    // a library/search song without connecting Spotify first — run the connect
    // handshake with the track URI: `authorizeAndPlayURI` authorizes, primes a
    // session, *and* starts the tapped song in one app switch, so there's no
    // separate Connect step. Once connected, the player state echo carries the
    // track back to the UI.
    guard let player = appRemote.playerAPI else {
      return await connect(playing: track.uri)
    }
    return await withCheckedContinuation { continuation in
      player.play(track.uri) { _, error in
        if let error {
          continuation.resume(returning: .failure(.providerRejected(error.localizedDescription)))
        } else {
          continuation.resume(returning: .success(()))
        }
      }
    }
  }

  // MARK: Direct Spotify Web API (no Furioke server proxy on iOS)

  func searchCatalog(query: String, limit: Int) async -> Result<[MusicTrack], MusicError> {
    guard let token = accessToken else { return .failure(.needsReconnect) }
    var components = URLComponents(string: "https://api.spotify.com/v1/search")!
    components.queryItems = [
      URLQueryItem(name: "q", value: query),
      URLQueryItem(name: "type", value: "track"),
      URLQueryItem(name: "limit", value: String(min(max(limit, 1), 50))),
    ]
    do {
      let envelope: SearchEnvelope = try await get(components.url!, token: token)
      return .success(envelope.tracks.items.map(Self.map))
    } catch {
      return .failure(Self.mapError(error))
    }
  }

  func resolveTracks(ids: [String]) async -> Result<[MusicTrack], MusicError> {
    guard let token = accessToken else { return .failure(.needsReconnect) }
    let bare = ids.map(Self.trackID(from:)).filter { !$0.isEmpty }
    guard !bare.isEmpty else { return .success([]) }
    var components = URLComponents(string: "https://api.spotify.com/v1/tracks")!
    components.queryItems = [URLQueryItem(
      name: "ids",
      value: bare.prefix(50).joined(separator: ",")
    )]
    do {
      let envelope: TracksEnvelope = try await get(components.url!, token: token)
      return .success(envelope.tracks.map(Self.map))
    } catch {
      return .failure(Self.mapError(error))
    }
  }

  // MARK: HTTP

  private enum HTTPError: Error { case unauthorized, badStatus(Int, String), notHTTP }

  private func get<T: Decodable>(_ url: URL, token: String) async throws -> T {
    var request = URLRequest(url: url)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw HTTPError.notHTTP }
    guard http.statusCode != 401 else { throw HTTPError.unauthorized }
    guard http.statusCode == 200 else {
      // Surface Spotify's error body — for a 400 it carries the exact reason
      // (e.g. "Only valid bearer authentication supported"), which is otherwise lost.
      let body = String(data: data, encoding: .utf8) ?? ""
      print("[Spotify] \(http.statusCode) \(url.absoluteString)\n  body: \(body)")
      throw HTTPError.badStatus(http.statusCode, body)
    }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(T.self, from: data)
  }

  private static func mapError(_ error: any Error) -> MusicError {
    switch error {
    case HTTPError.unauthorized: .needsReconnect
    case is CancellationError: .cancelled
    case let HTTPError.badStatus(code, body):
      .providerRejected("Spotify \(code): \(body)")
    default: .transportError("Couldn't reach Spotify.")
    }
  }

  // MARK: Emitting player state

  private func emit(
    track: MusicTrack?,
    positionMs: Int,
    durationMs: Int,
    isPlaying: Bool,
    error: MusicError? = nil
  ) {
    let update = MusicUpdate(
      provider: provider,
      connection: connection,
      track: track,
      positionMs: positionMs,
      durationMs: durationMs,
      isPlaying: isPlaying,
      playbackMode: "native-sdk",
      playbackError: error,
      playbackRate: 1
    )
    updatesContinuation?.yield(update)
  }

  fileprivate func emit(snapshot: PlayerSnapshot) {
    lastSnapshot = snapshot
    let trackID = Self.trackID(from: snapshot.uri)
    let artwork = artworkCache[trackID]
    let track = MusicTrack(
      provider: provider,
      providerTrackID: trackID,
      uri: snapshot.uri,
      title: snapshot.name,
      artists: [snapshot.artist],
      album: snapshot.album,
      durationMs: snapshot.durationMs,
      artworkURL: artwork
    )
    connection = .connected(provider)
    emit(
      track: track,
      positionMs: snapshot.positionMs,
      durationMs: snapshot.durationMs,
      isPlaying: snapshot.isPlaying
    )
    if artwork == nil, !trackID.isEmpty {
      resolveArtwork(for: trackID, query: "\(snapshot.name) \(snapshot.artist)")
    }
  }

  /// Resolve album artwork for an SDK-published (companion) track, then re-emit
  /// the current snapshot so the mini-player and Now Playing sheet pick it up.
  ///
  /// The obvious path — `/v1/tracks?ids=…` — is **forbidden (403)** for the token
  /// the App-Remote auth flow hands back (it carries playback scopes, and that
  /// metadata endpoint is gated for it), whereas `/v1/search` is permitted and is
  /// what the search flow already uses successfully. So we resolve via search:
  /// query the track's name + artist, prefer the result whose id matches exactly,
  /// and fall back to the top result's art when it doesn't rank in the page.
  /// Cached and de-duplicated so repeated player-state events don't refetch.
  private func resolveArtwork(for trackID: String, query: String) {
    guard artworkCache[trackID] == nil, !artworkInFlight.contains(trackID) else { return }
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return }
    artworkInFlight.insert(trackID)
    Task { [weak self] in
      guard let self else { return }
      defer { self.artworkInFlight.remove(trackID) }
      // The observed (companion) track has no synchronous artwork fallback —
      // unlike the search path's `.userInitiated` source — so this is its *only*
      // artwork source. Log non-happy outcomes (a silent `else { return }` once
      // hid the 403 that motivated this search-based path).
      let result = await searchCatalog(query: query, limit: MusicSearch.defaultLimit)
      guard case let .success(tracks) = result else {
        print("[Spotify] artwork resolve (search) failed for \(trackID): \(result)")
        return
      }
      // Prefer the exact track by id; search is fuzzy and the precise recording
      // often does not rank within the page, so fall back to the top match's art.
      // Same title + artist almost always shares the same cover, and the artwork
      // is decorative (thumbnail + ambient backdrop), not an identity claim.
      let match = tracks.first(where: { $0.providerTrackID == trackID }) ?? tracks.first
      guard let url = match?.artworkURL else {
        print("[Spotify] artwork resolve (search) found no usable art for \(trackID) "
          + "in \(tracks.count) results")
        return
      }
      artworkCache[trackID] = url
      // Re-emit only if this is still the current track.
      if let snapshot = lastSnapshot, Self.trackID(from: snapshot.uri) == trackID {
        emit(snapshot: snapshot)
      }
    }
  }

  // MARK: Main-actor hop

  //
  // SDK delegate callbacks are not guaranteed to arrive on the main thread (the
  // session-manager auth/token path in particular fires off-main), so we extract
  // only Sendable values in the `nonisolated` delegate, then run the main-actor
  // work here — synchronously when already on main, deferred otherwise. This
  // replaces a bare `MainActor.assumeIsolated`, which fatal-errors off-main.

  private nonisolated func runOnMain(_ work: @escaping @Sendable @MainActor () -> Void) {
    if Thread.isMainThread {
      MainActor.assumeIsolated(work)
    } else {
      Task { @MainActor in work() }
    }
  }

  // MARK: Helpers

  /// `spotify:track:abc` → `abc`; a bare id passes through unchanged.
  private static func trackID(from uri: String) -> String {
    uri.split(separator: ":").last.map(String.init) ?? uri
  }

  private static func map(_ track: SpotifyTrack) -> MusicTrack {
    MusicTrack(
      provider: .spotify,
      providerTrackID: track.id,
      uri: track.uri,
      title: track.name,
      artists: track.artists.map(\.name),
      album: track.album.name,
      durationMs: track.durationMs,
      artworkURL: track.album.images.first.flatMap { URL(string: $0.url) }
    )
  }

  /// Reads the (non-Sendable) SDK player state into a Sendable value off the main
  /// actor, so the delegate can hop to main without carrying SDK objects across.
  private nonisolated static func snapshot(from state: any SPTAppRemotePlayerState)
    -> PlayerSnapshot
  {
    let track = state.track
    return PlayerSnapshot(
      uri: track.uri,
      name: track.name,
      artist: track.artist.name,
      album: track.album.name,
      durationMs: Int(track.duration),
      positionMs: Int(state.playbackPosition),
      isPlaying: !state.isPaused
    )
  }
}

/// A Sendable copy of the SDK player state, safe to pass across the main-actor hop.
private struct PlayerSnapshot {
  let uri: String
  let name: String
  let artist: String
  let album: String
  let durationMs: Int
  let positionMs: Int
  let isPlaying: Bool
}

// MARK: - Spotify Web API DTOs

private struct SearchEnvelope: Decodable {
  let tracks: TrackItems
  struct TrackItems: Decodable { let items: [SpotifyTrack] }
}

private struct TracksEnvelope: Decodable {
  let tracks: [SpotifyTrack]
}

private struct SpotifyTrack: Decodable {
  let id: String
  let uri: String
  let name: String
  let durationMs: Int
  let artists: [NamedRef]
  let album: AlbumRef

  struct NamedRef: Decodable { let name: String }
  struct AlbumRef: Decodable {
    let name: String
    let images: [ImageRef]
    struct ImageRef: Decodable { let url: String }
  }
}

// MARK: - SDK delegates

//
// These are `nonisolated` so they can satisfy the ObjC delegate protocols on this
// `@MainActor` class. They may be invoked off the main thread, so each extracts
// only Sendable values and then runs the main-actor work via `runOnMain`.

extension SpotifyAdapter: SPTAppRemoteDelegate {
  nonisolated func appRemoteDidEstablishConnection(_: SPTAppRemote) {
    runOnMain { [self] in
      appRemote.playerAPI?.delegate = self
      appRemote.playerAPI?.subscribe(toPlayerState: nil)
      // Plain Connect primed a session only to attach App Remote — pause it now so
      // linking the account doesn't leave music playing. `playerStateDidChange`
      // then echoes the paused state, so the UI converges to "not playing".
      if pauseOnConnect {
        pauseOnConnect = false
        appRemote.playerAPI?.pause(nil)
      }
      appRemote.playerAPI?.getPlayerState { [self] result, _ in
        guard let state = result as? any SPTAppRemotePlayerState else { return }
        let snapshot = SpotifyAdapter.snapshot(from: state)
        runOnMain { [self] in emit(snapshot: snapshot) }
      }
      connection = .connected(provider)
      emit(track: nil, positionMs: 0, durationMs: 0, isPlaying: false)
      finishConnect(.success(()))
    }
  }

  nonisolated func appRemote(_: SPTAppRemote, didFailConnectionAttemptWithError _: (any Error)?) {
    runOnMain { [self] in
      let reason = MusicError
        .transportError("Couldn't connect to Spotify. Open the Spotify app and try again.")
      connection = .failed(provider, reason)
      // Emit so `MusicState` reflects the failure even on the foreground-revive path
      // (no awaiting `connect` continuation): connection flips to `.failed` and the
      // optimistic `isPlaying` clears, so the surface stops showing a dead "pause".
      emit(track: nil, positionMs: 0, durationMs: 0, isPlaying: false, error: reason)
      finishConnect(.failure(reason))
    }
  }

  nonisolated func appRemote(_: SPTAppRemote, didDisconnectWithError _: (any Error)?) {
    runOnMain { [self] in
      connection = .disconnected
      emit(track: nil, positionMs: 0, durationMs: 0, isPlaying: false)
    }
  }
}

extension SpotifyAdapter: SPTAppRemotePlayerStateDelegate {
  nonisolated func playerStateDidChange(_ playerState: any SPTAppRemotePlayerState) {
    let snapshot = Self.snapshot(from: playerState)
    runOnMain { [self] in emit(snapshot: snapshot) }
  }
}
