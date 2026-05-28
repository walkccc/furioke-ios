import Foundation

nonisolated enum MusicProvider: String, CaseIterable, Codable, Identifiable, Sendable {
  case spotify
  case appleMusic
  case youtube

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .spotify: "Spotify"
    case .appleMusic: "Apple Music"
    case .youtube: "YouTube"
    }
  }
}

nonisolated struct MusicTrack: Identifiable, Equatable, Hashable, Sendable {
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

nonisolated struct MusicAccount: Equatable, Sendable {
  let provider: MusicProvider
  let displayName: String
}

nonisolated enum MusicControl: Equatable, Sendable {
  case play
  case pause
  case previous
  case next
  case seek(positionMs: Int)
}

nonisolated enum MusicError: Error, Equatable, Sendable {
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

nonisolated enum MusicConnection: Equatable, Sendable {
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

nonisolated struct MusicUpdate: Equatable, Sendable {
  let provider: MusicProvider
  let connection: MusicConnection
  let track: MusicTrack?
  let positionMs: Int
  let durationMs: Int
  let isPlaying: Bool
  let playbackMode: String?
  let playbackError: MusicError?
}

nonisolated enum PlaybackSource: Equatable, Sendable {
  case userInitiated(MusicTrack)
  case observed(MusicTrack)

  var track: MusicTrack {
    switch self {
    case let .userInitiated(track), let .observed(track):
      track
    }
  }

  var labelPrefix: String {
    switch self {
    case .userInitiated: "Playing on"
    case .observed: "Companion"
    }
  }
}

@MainActor
protocol MusicSource: AnyObject {
  var provider: MusicProvider { get }
  var requiresAccount: Bool { get }
  var supportsRepeat: Bool { get }
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
