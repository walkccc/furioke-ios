import Foundation

nonisolated enum MusicProvider: String, CaseIterable, Codable, Identifiable {
  case spotify
  case appleMusic = "apple-music"
  case youtube

  var id: String {
    rawValue
  }

  var displayName: String {
    switch self {
    case .spotify: "Spotify"
    case .appleMusic: "Apple Music"
    case .youtube: "YouTube"
    }
  }

  /// Reconstruct a playback URI from a stored provider track id. Saved songs (and
  /// the Supabase `songs` table they mirror) persist only `(provider,
  /// providerTrackID)` and let the adapter resolve artwork, so the URI is rebuilt
  /// here when replaying a track from the Library.
  func playbackURI(forTrackID id: String) -> String {
    switch self {
    case .spotify: "spotify:track:\(id)"
    case .appleMusic: id
    // The provider track id for YouTube *is* the video id; the watch URL is the
    // external hand-off form ("view on YouTube"), while in-app playback loads the
    // bare video id into the IFrame player.
    case .youtube: "https://www.youtube.com/watch?v=\(id)"
    }
  }
}

/// Whether a `MusicSource` requires a visible player surface mounted in the UI.
/// Headless sources (Spotify drives the out-of-process Spotify app, Apple Music
/// drives `ApplicationMusicPlayer`) report `.none`; YouTube reports `.video`
/// because the only ToS-compliant playback route is the IFrame Player rendered in
/// a visible `WKWebView`. Feature/view code mounts a player by reading this
/// capability — never by comparing against a specific provider.
nonisolated enum MusicPlayerSurface: Equatable {
  case none
  case video
}

nonisolated struct MusicTrack: Identifiable, Equatable, Hashable {
  let provider: MusicProvider
  let providerTrackID: String
  let uri: String
  let title: String
  let artists: [String]
  let album: String?
  let durationMs: Int
  let artworkURL: URL?

  var id: String {
    "\(provider.rawValue):\(providerTrackID)"
  }

  var artistDisplayName: String {
    let joined = artists.filter { !$0.isEmpty }.joined(separator: ", ")
    return joined.isEmpty ? "Unknown artist" : joined
  }

  var durationText: String {
    let seconds = max(durationMs, 0) / 1_000
    return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
  }
}

nonisolated struct MusicAccount: Equatable {
  let provider: MusicProvider
  let displayName: String
}

nonisolated enum MusicControl: Equatable {
  case play
  case pause
  case previous
  case next
  case seek(positionMs: Int)
}

nonisolated enum MusicError: Error, Equatable {
  case notInstalled
  case userCancelled
  case handshakeTimeout
  case transportError(String)
  case renewFailed
  case cancelled
  case needsReconnect
  case providerRejected(String)
  case unsupported
  case unplayable
  case embedDisabled
  case notFound
  case regionLocked
  case playbackDidNotStart

  var userMessage: String? {
    switch self {
    case .notInstalled:
      "Spotify isn't installed."
    case .userCancelled, .cancelled, .renewFailed:
      nil
    case .handshakeTimeout:
      "Spotify didn't respond. Try again."
    case let .transportError(message):
      message
    case .needsReconnect:
      "Connect Spotify to keep listening."
    case let .providerRejected(message):
      message
    case .unsupported:
      "This provider doesn't support that action."
    case .unplayable:
      "This track can't be played."
    case .embedDisabled:
      "Playback is disabled for this track."
    case .notFound:
      "That track couldn't be found."
    case .regionLocked:
      "This track isn't available in your region."
    case .playbackDidNotStart:
      "Playback didn't start. Try again."
    }
  }
}

nonisolated enum MusicConnection: Equatable {
  case disconnected
  case connecting(MusicProvider)
  case connected(MusicProvider)
  case failed(MusicProvider, MusicError)

  var isConnected: Bool {
    if case .connected = self { return true }
    return false
  }

  var error: MusicError? {
    if case let .failed(_, error) = self { return error }
    return nil
  }
}

nonisolated struct MusicUpdate: Equatable {
  let provider: MusicProvider
  let connection: MusicConnection
  let track: MusicTrack?
  let positionMs: Int
  let durationMs: Int
  let isPlaying: Bool
  let playbackMode: String?
  let playbackError: MusicError?
}

nonisolated enum PlaybackSource: Equatable {
  case userInitiated(MusicTrack)
  case observed(MusicTrack)

  var track: MusicTrack {
    switch self {
    case let .userInitiated(track), let .observed(track):
      track
    }
  }
}

/// Catalog-search tuning shared across the playback layer and provider adapters.
nonisolated enum MusicSearch {
  /// Default `/v1/search` page size. Spotify rejects larger page sizes for the
  /// App-Remote access token (`400 Invalid limit`), so both the default catalog
  /// search and artwork resolution cap at this conservative value.
  static let defaultLimit = 10
}

@MainActor
protocol MusicSource: AnyObject {
  var provider: MusicProvider { get }
  var requiresAccount: Bool { get }
  var supportsRepeat: Bool { get }
  /// Whether this source needs a visible player surface mounted in the UI.
  /// Defaults to `.none`; only view-backed sources (YouTube) override it.
  var playerSurface: MusicPlayerSurface { get }
  var updates: AsyncStream<MusicUpdate> { get }

  func getConnection() -> MusicConnection
  func getAccount() async -> MusicAccount?
  func connect() async -> Result<Void, MusicError>
  func disconnect() async
  func control(_ control: MusicControl) async -> Result<Void, MusicError>
  func playTrack(_ track: MusicTrack) async -> Result<Void, MusicError>
  func resolveTracks(ids: [String]) async -> Result<[MusicTrack], MusicError>
  func searchCatalog(query: String, limit: Int) async -> Result<[MusicTrack], MusicError>
}

extension MusicSource {
  /// Headless default: Spotify and Apple Music inherit this and need no player
  /// surface. YouTube overrides it with `.video`.
  var playerSurface: MusicPlayerSurface {
    .none
  }
}
