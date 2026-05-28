import Foundation

/// Fetches a raw LRC (or plain) lyric body for a track from the Furioke Workers
/// API (`GET /api/lyrics`), authenticated with the user's Supabase bearer token.
/// The response shape mirrors the web's `app/api/lyrics/route.ts` exactly; the
/// raw body is the persisted form and is fed straight
/// into the local furigana pipeline.
struct LyricsService {
  private let auth: AuthService
  private let baseURL: URL

  init(auth: AuthService, baseURL: URL = BackendConfig.apiBaseURL) {
    self.auth = auth
    self.baseURL = baseURL
  }

  enum LyricsError: Error { case requestFailed(Int) }

  /// The lyric body for `track`, preferring synced (timestamped) lyrics over
  /// plain. Returns `nil` when LRCLIB has no entry for the track.
  func fetchBody(for track: MusicTrack) async throws -> LyricFetchResult? {
    let token = try await auth.validAccessToken()

    var components = URLComponents(
      url: baseURL.appendingPathComponent("api/lyrics"),
      resolvingAgainstBaseURL: false
    )!
    components.queryItems = [
      URLQueryItem(name: "track", value: track.title),
      URLQueryItem(name: "artist", value: track.artists.first ?? track.artistDisplayName),
      URLQueryItem(name: "album", value: track.album ?? ""),
      URLQueryItem(name: "duration", value: String(max(track.durationMs, 0) / 1_000)),
    ]

    var request = URLRequest(url: components.url!)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
      throw LyricsError.requestFailed((response as? HTTPURLResponse)?.statusCode ?? -1)
    }

    let payload = try JSONDecoder().decode(LyricsResponse.self, from: data)
    guard payload.found, let body = payload.syncedLyrics ?? payload.plainLyrics else { return nil }
    return LyricFetchResult(body: body, lrclibID: payload.lrclibId)
  }
}

/// The lyric payload cached and rendered: the raw body plus the LRCLIB id from the
/// response. `Equatable` so the read-through cache can skip a re-render when a
/// background revalidation returns an unchanged body.
nonisolated struct LyricFetchResult: Equatable {
  let body: String
  let lrclibID: String?
}

/// Mirror of the `/api/lyrics` success payload.
private struct LyricsResponse: Decodable {
  let found: Bool
  let synced: Bool?
  let syncedLyrics: String?
  let plainLyrics: String?
  let lrclibId: String?
}
