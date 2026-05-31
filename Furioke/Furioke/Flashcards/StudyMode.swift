import Foundation

/// The study session's recognition ladder: each rung strips one reading aid from
/// the card's prompt face, while the reveal always completes the full word
/// (kanji · reading · meaning · lyric). For a Chinese reader the kanji give the
/// meaning away, so the ladder removes that crutch step by step — ending at
/// `hiragana`, where the kanji is gone and only the sound remains. Persisted as
/// the raw value via `FlashcardDisplayDefaults.studyMode`; `read` is the default
/// rung and reproduces the original kanji-front behavior.
nonisolated enum StudyMode: String, CaseIterable, Identifiable {
  /// Kanji with per-kanji furigana above it (the lyric-surface ruby) — recognize
  /// only.
  case glance
  /// Kanji with no reading — produce the reading. The default.
  case read
  /// The reading alone, no kanji — no character crutch.
  case hiragana

  var id: String { rawValue }

  var title: String {
    switch self {
    case .glance: "Glance"
    case .read: "Read"
    case .hiragana: "Hiragana"
    }
  }
}
