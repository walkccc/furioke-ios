import Foundation
import Observation
import StoreKit
import SwiftUI

/// Drives the native App Store review prompt, buried in the core flow rather than
/// fronted by a button: the app asks only after the user has actually read along
/// to a handful of songs — its reason to exist — so the request lands on a genuine
/// value moment instead of a cold first launch.
///
/// This owns only the *when*; the *how* stays in the view layer, because the
/// system prompt can be presented exclusively through SwiftUI's
/// `requestReview` action. `recordSongViewed()` counts value moments and arms
/// `shouldRequestReview`; the host view (`AppShell`) watches that flag, fires the
/// action at a logical pause, and calls `markRequested()` to disarm it.
///
/// StoreKit itself caps the real prompt to a few times a year and may show
/// nothing at all, so the only job here is to avoid wasting that budget: the
/// request is armed at most once per app version (`lastVersionPrompted`).
@Observable
@MainActor
final class RatingPromptController {
  private enum Key {
    static let songsViewed = "furioke.rating.songsViewed"
    static let lastVersionPrompted = "furioke.rating.lastVersionPrompted"
  }

  /// How many songs the user reads lyrics for before the app asks for a review.
  /// Set past the first couple of songs so the prompt never lands on a fresh
  /// install and only after the core loop has clearly delivered.
  private static let promptThreshold = 3

  private let defaults: UserDefaults
  private let appVersion: String

  /// Armed when the user crosses the song-view threshold and this app version
  /// hasn't already asked. `AppShell` watches this and presents the system prompt
  /// at a logical pause (when Now Playing is dismissed), then calls
  /// `markRequested()`.
  private(set) var shouldRequestReview = false

  init(
    defaults: UserDefaults = .standard,
    appVersion: String = Bundle.main.shortVersionString
  ) {
    self.defaults = defaults
    self.appVersion = appVersion
  }

  /// Record one successful lyric view — the app's core value moment. Crossing the
  /// threshold arms a review request, but only while this app version hasn't asked
  /// yet: once armed-and-fired for a version, the counter stops mattering until the
  /// next update, so we never re-pester on every launch.
  func recordSongViewed() {
    guard defaults.string(forKey: Key.lastVersionPrompted) != appVersion else { return }
    let count = defaults.integer(forKey: Key.songsViewed) + 1
    defaults.set(count, forKey: Key.songsViewed)
    if count >= Self.promptThreshold {
      shouldRequestReview = true
    }
  }

  /// Disarm the flag and stamp this app version, so the host fires the system
  /// prompt at most once per version. Called right after `AppShell` invokes the
  /// `requestReview` action.
  func markRequested() {
    shouldRequestReview = false
    defaults.set(appVersion, forKey: Key.lastVersionPrompted)
  }
}

private extension Bundle {
  /// `CFBundleShortVersionString` (e.g. "1.4.0"), the marketing version the
  /// per-version prompt gate keys on. Falls back to "0" if the key is ever absent.
  var shortVersionString: String {
    object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
  }
}
