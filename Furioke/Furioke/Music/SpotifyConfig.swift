import Foundation

enum SpotifyConfig {
  static let clientID: String = {
    guard
      let value = Bundle.main.object(forInfoDictionaryKey: "SPOTIFY_CLIENT_ID") as? String,
      !value.isEmpty
    else {
      fatalError("SPOTIFY_CLIENT_ID is missing in Info.plist")
    }
    return value
  }()

  static let redirectURL: URL = {
    guard
      let raw = Bundle.main.object(forInfoDictionaryKey: "SPOTIFY_REDIRECT_URL") as? String,
      let url = URL(string: raw)
    else {
      fatalError("SPOTIFY_REDIRECT_URL is missing or malformed in Info.plist")
    }
    return url
  }()
}
