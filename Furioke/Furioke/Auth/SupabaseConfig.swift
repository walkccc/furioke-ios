import Foundation

/// Furioke's Supabase project coordinates. The URL and publishable (anon) key are
/// client-safe by design — they ship in any client binary and the web app exposes
/// them via `NEXT_PUBLIC_*`. They live in Info.plist so the value is one edit away
/// from a build setting / xcconfig later without touching source.
enum SupabaseConfig {
  static let redirectURL = URL(string: "furioke://auth/callback")!

  static let url: URL = {
    guard
      let raw = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
      let url = URL(string: raw)
    else {
      fatalError("SUPABASE_URL is missing or malformed in Info.plist")
    }
    return url
  }()

  static let anonKey: String = {
    guard
      let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
      !key.isEmpty
    else {
      fatalError("SUPABASE_ANON_KEY is missing in Info.plist")
    }
    return key
  }()
}
