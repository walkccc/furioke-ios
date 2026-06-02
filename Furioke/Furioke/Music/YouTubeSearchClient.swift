import Foundation

/// Client for the `youtube-search` Supabase Edge Function — the InnerTube proxy
/// that resolves a query (or a set of video ids) to playable YouTube videos.
///
/// The InnerTube logic itself lives **server-side** (separate backend/web repo)
/// so it can be hotfixed without an App Store release when Google rotates its
/// internal client keys / request shapes; iOS depends only on the stable
/// request/response contract defined here, and never calls the official YouTube
/// Data API. The function also owns the `normalizedQuery → results` cache.
///
/// ## Contract
///
/// `POST {SUPABASE_URL}/functions/v1/youtube-search`
/// (auth: Supabase `apikey` + `Authorization: Bearer <anonKey>`)
///
/// - **Search:** body `{ "q": String, "limit": Int }` →
///   `{ "results": [ { "videoId", "title", "artists": [String], "durationMs": Int,
///   "thumbnailUrl": String? } ] }`
/// - **Resolve:** body `{ "videoIds": [String] }` → same `results` envelope.
/// - **Invalidate:** body `{ "invalidateVideoId": String }` → drops the cache
///   entry that produced a now-dead video id so the next search re-resolves a live
///   one (called by the IFrame error bridge on codes 100 / 101 / 150).
///
/// On any non-2xx / transport / decoding failure the search/resolve calls throw so
/// the adapter can surface a "temporarily unavailable" state rather than hang.
struct YouTubeSearchClient {
  struct Result: Decodable {
    let videoId: String
    let title: String
    let artists: [String]
    let durationMs: Int
    let thumbnailUrl: String?
  }

  private struct Envelope: Decodable { let results: [Result] }

  private var endpoint: URL {
    SupabaseConfig.url
      .appendingPathComponent("functions")
      .appendingPathComponent("v1")
      .appendingPathComponent("youtube-search")
  }

  func search(query: String, limit: Int) async throws -> [Result] {
    let envelope: Envelope = try await post(["q": query, "limit": limit])
    return envelope.results
  }

  func resolve(videoIds: [String]) async throws -> [Result] {
    guard !videoIds.isEmpty else { return [] }
    let envelope: Envelope = try await post(["videoIds": videoIds])
    return envelope.results
  }

  /// Best-effort: ask the function to drop the cache entry that produced a dead
  /// video id. Failures are swallowed — the worst case is a stale entry that the
  /// next play attempt re-trips.
  func invalidate(videoId: String) async {
    _ = try? await postRaw(["invalidateVideoId": videoId])
  }

  private func post<T: Decodable>(_ body: [String: Any]) async throws -> T {
    let data = try await postRaw(body)
    return try JSONDecoder().decode(T.self, from: data)
  }

  @discardableResult
  private func postRaw(_ body: [String: Any]) async throws -> Data {
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
    request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
      throw URLError(.badServerResponse)
    }
    return data
  }
}
