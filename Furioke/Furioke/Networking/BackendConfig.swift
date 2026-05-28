import Foundation

/// The Furioke Workers API base URL (`/api/lyrics`, `/api/translate`, …). Like
/// `SupabaseConfig` / `SpotifyConfig`, it lives in Info.plist so the value is one
/// edit away from a build setting / xcconfig later without touching source.
enum BackendConfig {
  static let apiBaseURL: URL = {
    guard
      let raw = Bundle.main.object(forInfoDictionaryKey: "FURIOKE_API_BASE_URL") as? String,
      let url = URL(string: raw)
    else {
      fatalError("FURIOKE_API_BASE_URL is missing or malformed in Info.plist")
    }
    return url
  }()
}
