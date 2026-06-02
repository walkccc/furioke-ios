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
  case en
  case ja
  case zh

  var id: String {
    rawValue
  }

  var label: String {
    switch self {
    case .en: "English"
    case .ja: "日本語"
    case .zh: "中文"
    }
  }

  /// Overrides the UI locale (matches the web app's i18n set: en / ja / zh).
  var locale: Locale? {
    switch self {
    case .en: Locale(identifier: "en")
    case .ja: Locale(identifier: "ja")
    // Traditional Chinese, matching the `zh-tw` native-language target and the
    // `zh-Hant` localization in the String Catalog.
    case .zh: Locale(identifier: "zh-Hant")
    }
  }
}

/// The learner's native (explanation) language — the axis that drives the
/// translation target, independent of the app/interface `LanguagePreference`.
/// Only real translation targets are offered: English and Traditional Chinese.
/// Japanese is deliberately absent (translating Japanese lyrics/glosses into
/// Japanese is a no-op for learners), though `日本語` stays a valid interface
/// language.
enum NativeLanguagePreference: String, CaseIterable, Identifiable {
  case en
  case zh

  var id: String {
    rawValue
  }

  var label: String {
    switch self {
    case .en: "English"
    case .zh: "中文"
    }
  }

  /// The `/api/translate` target language for learner-facing translation (the
  /// lyric translation toggle and flashcard glosses). `zh` maps to Traditional
  /// Chinese, matching the web route's supported targets and the gloss keyspace.
  var translationTarget: String {
    switch self {
    case .en: "en"
    case .zh: "zh-tw"
    }
  }

  /// The default native language for a fresh install, derived from the chosen
  /// app language so existing behavior is reproduced until the user overrides
  /// it: a Chinese interface (`中文`) defaults to `中文`; everything else
  /// defaults to English.
  static func derived(from language: LanguagePreference) -> NativeLanguagePreference {
    switch language {
    case .zh: .zh
    default: .en
    }
  }
}

@Observable
@MainActor
final class PreferencesState {
  private enum Key {
    static let theme = "furioke.preferences.theme"
    static let language = "furioke.preferences.language"
    static let nativeLanguage = "furioke.preferences.nativeLanguage"
    static let onboardingCompleted = "furioke.preferences.onboardingCompleted"
  }

  private let defaults: UserDefaults

  var theme: ThemePreference {
    didSet { defaults.set(theme.rawValue, forKey: Key.theme) }
  }

  var language: LanguagePreference {
    didSet { defaults.set(language.rawValue, forKey: Key.language) }
  }

  var nativeLanguage: NativeLanguagePreference {
    didSet { defaults.set(nativeLanguage.rawValue, forKey: Key.nativeLanguage) }
  }

  /// Whether the first-launch onboarding flow has been completed or skipped on
  /// this device. Defaults to `false` on a fresh install; set once (and never
  /// reset) so onboarding shows exactly once. Written through to `UserDefaults`
  /// like every other preference so a force-quit keeps the choice.
  var hasCompletedOnboarding: Bool {
    didSet { defaults.set(hasCompletedOnboarding, forKey: Key.onboardingCompleted) }
  }

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    theme = defaults.string(forKey: Key.theme)
      .flatMap(ThemePreference.init(rawValue:)) ?? .system
    let language = defaults.string(forKey: Key.language)
      .flatMap(LanguagePreference.init(rawValue:)) ?? .en
    self.language = language
    // Absent native language → derive from the app language so existing users
    // keep their current target until they explicitly choose one.
    nativeLanguage = defaults.string(forKey: Key.nativeLanguage)
      .flatMap(NativeLanguagePreference.init(rawValue:))
      ?? .derived(from: language)
    // Absent key → not yet onboarded (a fresh install), so the flow presents.
    hasCompletedOnboarding = defaults.bool(forKey: Key.onboardingCompleted)
  }

  /// Mark the first-launch onboarding flow as done. The single seam both the
  /// "Get started" completion and every "Skip" affordance route through, so
  /// completion is set in exactly one place.
  func completeOnboarding() {
    hasCompletedOnboarding = true
  }

  /// Re-present the onboarding flow from the start. Driven by the Settings
  /// "Replay Tutorial" row: clearing the flag flips the `AppShell` cover's
  /// presentation binding back on, and the flow's `step` resets to `.welcome`
  /// because it is presented fresh.
  func restartOnboarding() {
    hasCompletedOnboarding = false
  }

  /// The locale to push into the environment; `nil` means "let the system decide".
  var resolvedLocale: Locale? {
    language.locale
  }

  /// The single learner-facing translation target, driven by the native
  /// language and independent of the interface `locale`. Every consumer (lyric
  /// translation, flashcard glosses) reads the target from here.
  var translationTarget: String {
    nativeLanguage.translationTarget
  }
}
