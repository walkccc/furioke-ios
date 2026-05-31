import Foundation

/// Leitner-style spaced repetition, a verbatim port of
/// `../furioke/lib/flashcards/schedule.ts`. A card's `level` indexes a fixed
/// interval, so the whole schedule is two stored fields and a lookup —
/// transparent and easy to test. A future SM-2 upgrade is a schedule swap, not a
/// schema change.
///
/// Level 0 is "new / lapsed" and due immediately; each promotion lengthens the
/// gap before the card returns, and the last interval is the ceiling. `now` is
/// injected on every entry point for testability, matching the web.
nonisolated enum FlashcardSchedule {
  static let intervalDaysByLevel = [0, 1, 3, 7, 16, 35]
  static let maxLevel = intervalDaysByLevel.count - 1
  private static let dayInterval: TimeInterval = 24 * 60 * 60

  static func intervalDays(forLevel level: Int) -> Int {
    let clamped = max(0, min(level, maxLevel))
    return intervalDaysByLevel[clamped]
  }

  /// Pure scheduler. "gotIt" promotes one box (capped) and pushes `dueAt` out by
  /// the new level's interval; "again" drops the card back to box 0, due now, so
  /// it re-queues in the current study session.
  static func grade(_ card: Flashcard, _ grade: FlashcardGrade, now: Date) -> Flashcard {
    var next = card
    next.updatedAt = now
    switch grade {
    case .again:
      next.level = 0
      next.dueAt = now
    case .gotIt:
      let level = min(card.level + 1, maxLevel)
      next.level = level
      next.dueAt = now.addingTimeInterval(Double(intervalDays(forLevel: level)) * dayInterval)
    }
    return next
  }

  static func isDue(_ card: Flashcard, now: Date) -> Bool {
    card.dueAt <= now
  }
}
