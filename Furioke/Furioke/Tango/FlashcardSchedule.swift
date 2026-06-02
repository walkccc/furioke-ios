import Foundation

/// Leitner-style spaced repetition, ported verbatim from the web
/// (`lib/flashcards/schedule.ts`). A card's `level` indexes a fixed interval, so
/// the whole schedule is two stored fields and a lookup. Level 0 is "new /
/// lapsed" and due immediately; each promotion lengthens the gap before the card
/// returns; the last interval is the ceiling. A future SM-2 upgrade is a schedule
/// swap, not a schema change.
nonisolated enum FlashcardSchedule {
  /// Days before a card at each level becomes due again. Index = level; the last
  /// entry is the ceiling. Must match the web's `INTERVAL_DAYS`.
  static let intervalDaysByLevel = [0, 1, 3, 7, 16, 35]
  static let maxLevel = intervalDaysByLevel.count - 1

  private static let day: TimeInterval = 24 * 60 * 60

  static func intervalDays(forLevel level: Int) -> Int {
    intervalDaysByLevel[max(0, min(level, maxLevel))]
  }

  /// Apply a grade, returning a copy of `card` with updated schedule fields and
  /// `updatedAt`. "Got it" promotes one box (capped at `maxLevel`) and pushes
  /// `dueAt` out by the new level's interval; "Again" drops the card to box 0,
  /// due now, so it re-queues in the current session. `now` is injected for
  /// testability. Mirrors the web's `gradeCard`.
  static func grade(_ card: Flashcard, _ grade: FlashcardGrade, now: Date = .now) -> Flashcard {
    var card = card
    switch grade {
    case .again:
      card.level = 0
      card.dueAt = now
    case .gotIt:
      card.level = min(card.level + 1, maxLevel)
      card.dueAt = now.addingTimeInterval(TimeInterval(intervalDays(forLevel: card.level)) * day)
    }
    card.updatedAt = now
    return card
  }
}
