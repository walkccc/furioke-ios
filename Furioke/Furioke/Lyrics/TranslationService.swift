import Foundation

/// Whole-body lyric translation via the Furioke Workers API
/// (`POST /api/translate`), authenticated with the user's Supabase bearer token.
/// The request mirrors the web route exactly: `{ text, target }`, where `text` is
/// the lyric body (one line per lyric line) and the response `{ translated }`
/// carries one translated line per input line. Results are runtime-only
/// server-side; the iOS client caches them in `TranslationEntity`.
struct TranslationService {
  /// Recorded on each cached translation so a future model change can invalidate
  /// stale entries. The route does not echo the model, so it is pinned here to the
  /// model the web route uses.
  static let modelVersion = "claude-haiku-4-5-20251001"

  private let auth: AuthService
  private let baseURL: URL

  init(auth: AuthService, baseURL: URL = BackendConfig.apiBaseURL) {
    self.auth = auth
    self.baseURL = baseURL
  }

  enum TranslationError: Error { case requestFailed(Int) }

  /// The translated body for `text` in `target` (e.g. `en`, `zh-tw`), or `nil`
  /// when there is nothing to translate. Non-200s (401 auth, 429 quota, 502
  /// provider) throw so the caller can fall back to cache or a quiet notice.
  func translate(text: String, target: String) async throws -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let token = try await auth.validAccessToken()
    var request = URLRequest(url: baseURL.appendingPathComponent("api/translate"))
    request.httpMethod = "POST"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(TranslateRequest(text: text, target: target))

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
      throw TranslationError.requestFailed((response as? HTTPURLResponse)?.statusCode ?? -1)
    }
    return try JSONDecoder().decode(TranslateResponse.self, from: data).translated
  }
}

private struct TranslateRequest: Encodable {
  let text: String
  let target: String
}

private struct TranslateResponse: Decodable {
  let translated: String
}
