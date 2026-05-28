import Observation
import SwiftUI

// Root-injected user preferences: one `@Observable` slice for the
// chrome-level appearance + language choices. Persistence is plain `UserDefaults`;
// the defaults are written
// through on every set so a force-quit keeps the choice.

enum ThemePreference: String, CaseIterable, Identifiable {
  case system
  case light
  case dark

  var id: String {
    rawValue
  }

  var label: String {
    switch self {
    case .system: "System"
    case .light: "Light"
    case .dark: "Dark"
    }
  }

  /// `nil` lets SwiftUI follow the device appearance; the explicit cases pin it.
  var colorScheme: ColorScheme? {
    switch self {
    case .system: nil
    case .light: .light
    case .dark: .dark
    }
  }
}

enum LanguagePreference: String, CaseIterable, Identifiable {
  case system
  case en
  case ja
  case zh

  var id: String {
    rawValue
  }

  var label: String {
    switch self {
    case .system: "System"
    case .en: "English"
    case .ja: "日本語"
    case .zh: "中文"
    }
  }

  /// `nil` follows the device locale; the explicit cases override the UI locale
  /// (matches the web app's i18n set: en / ja / zh).
  var locale: Locale? {
    switch self {
    case .system: nil
    case .en: Locale(identifier: "en")
    case .ja: Locale(identifier: "ja")
    case .zh: Locale(identifier: "zh")
    }
  }

  /// The `/api/translate` target language for the lyric translation toggle.
  /// Chinese maps to Traditional (`zh-tw`), matching the web route's
  /// supported targets; `system` resolves from the device language.
  var translationTarget: String {
    switch self {
    case .en: "en"
    case .ja: "ja"
    case .zh: "zh-tw"
    case .system:
      switch Locale.current.language.languageCode?.identifier {
      case "zh": "zh-tw"
      case "ja": "ja"
      default: "en"
      }
    }
  }
}

@Observable
@MainActor
final class PreferencesState {
  private enum Key {
    static let theme = "furioke.preferences.theme"
    static let language = "furioke.preferences.language"
  }

  private let defaults: UserDefaults

  var theme: ThemePreference {
    didSet { defaults.set(theme.rawValue, forKey: Key.theme) }
  }

  var language: LanguagePreference {
    didSet { defaults.set(language.rawValue, forKey: Key.language) }
  }

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    theme = defaults.string(forKey: Key.theme)
      .flatMap(ThemePreference.init(rawValue:)) ?? .system
    language = defaults.string(forKey: Key.language)
      .flatMap(LanguagePreference.init(rawValue:)) ?? .system
  }

  /// The locale to push into the environment; `nil` means "let the system decide".
  var resolvedLocale: Locale? {
    language.locale
  }
}
