import SwiftUI

/// `UserDefaults` keys for the flashcard display toggles, shared so the deck and
/// study screens read the same `@AppStorage`-backed preference. `showFurigana`
/// renders each saved word's reading as ruby stacked above the surface (off
/// drops the reading row); `showSourceLine` reveals the lyric line the word was
/// captured from. Both default to on.
enum FlashcardDisplayDefaults {
  static let showFurigana = "furioke.flashcards.showFurigana"
  static let showSourceLine = "furioke.flashcards.showSourceLine"
  /// The study session's recognition mode (`StudyMode.rawValue`); persisted so the
  /// chosen rung of the difficulty ladder survives across sessions. Read only by
  /// the study screen — the deck list is unaffected.
  static let studyMode = "furioke.flashcards.studyMode"
  /// The deck browse list's sort order (`DeckSort.rawValue`); persisted so the
  /// learner's chosen ordering survives across launches. Affects only the deck
  /// list — study sequencing always follows the spaced-repetition schedule.
  static let deckSort = "furioke.flashcards.deckSort"
}

/// How the deck browse list is ordered. Independent of study sequencing, which
/// always pulls due cards by the schedule (`FlashcardsState.dueCards`).
enum DeckSort: String, CaseIterable, Identifiable {
  /// Newest save first — the prior fixed behavior (by `createdAt`).
  case added
  /// Soonest due first, so the cards needing attention surface at the top.
  case due
  /// By reading, so the deck reads like a kana-ordered glossary.
  case alphabetical
  /// Least-mastered first (lowest Leitner level), a study-triage view.
  case mastery

  var id: String { rawValue }

  var label: String {
    switch self {
    case .added: "Date added"
    case .due: "Due date"
    case .alphabetical: "A–Z"
    case .mastery: "Mastery"
    }
  }

  /// Order two cards under this sort. Ties fall back to newest-added so the
  /// order is stable and total.
  func areInIncreasingOrder(_ a: Flashcard, _ b: Flashcard) -> Bool {
    switch self {
    case .added: a.createdAt > b.createdAt
    case .due: a.dueAt != b.dueAt ? a.dueAt < b.dueAt : a.createdAt > b.createdAt
    case .alphabetical:
      a.reading != b.reading
        ? a.reading.localizedStandardCompare(b.reading) == .orderedAscending
        : a.createdAt > b.createdAt
    case .mastery: a.level != b.level ? a.level < b.level : a.createdAt > b.createdAt
    }
  }
}

/// A quick filter over the deck browse list. Layered on top of search. Not
/// persisted — it resets each visit, unlike the sort. `needsReview` is the low
/// end of the Leitner ladder (new / lapsed / barely learned).
enum DeckFilter: Hashable {
  case all
  case dueNow
  case needsReview
  case song(String)

  /// Boxes 0–1 count as "needs review": new, lapsed, or only just promoted.
  static let needsReviewMaxLevel = 1

  func matches(_ card: Flashcard, now: Date) -> Bool {
    switch self {
    case .all: true
    case .dueNow: FlashcardSchedule.isDue(card, now: now)
    case .needsReview: card.level <= Self.needsReviewMaxLevel
    case let .song(title): card.sourceTitle == title
    }
  }
}

/// The Study tab's root: the signed-in learner's flashcard deck. Lists every
/// saved card with its source context, supports search and swipe-to-delete, and
/// links into study mode for the cards due now. Reads `FlashcardsState` (the
/// in-memory mirror of the server-backed deck) so it reflects saves made on the
/// lyric surface immediately and renders offline.
struct DeckView: View {
  @Environment(FlashcardsState.self) private var flashcards
  @Environment(PreferencesState.self) private var preferences
  @State private var query = ""
  @State private var filter: DeckFilter = .all
  @AppStorage(FlashcardDisplayDefaults.showFurigana) private var showFurigana = true
  @AppStorage(FlashcardDisplayDefaults.showSourceLine) private var showSourceLine = true
  @AppStorage(FlashcardDisplayDefaults.deckSort) private var deckSortRaw = DeckSort.added.rawValue

  /// The active language's gloss key — what the deck displays and searches.
  private var target: String { preferences.language.translationTarget }

  private var sort: DeckSort { DeckSort(rawValue: deckSortRaw) ?? .added }

  /// The distinct source songs in the deck, for the "by song" filter.
  private var songs: [String] {
    var seen = Set<String>()
    return flashcards.cards.compactMap { card in
      guard let title = card.sourceTitle, !title.isEmpty, seen.insert(title).inserted
      else { return nil }
      return title
    }
  }

  /// The deck after the active filter, then the search query (matched against
  /// surface, reading, and the active language's meaning), then the chosen sort.
  private var filtered: [Flashcard] {
    let now = Date.now
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return flashcards.cards
      .filter { filter.matches($0, now: now) }
      .filter { card in
        guard !q.isEmpty else { return true }
        return card.surface.lowercased().contains(q)
          || card.reading.lowercased().contains(q)
          || (card.meaning(for: target)?.lowercased().contains(q) ?? false)
      }
      .sorted(by: sort.areInIncreasingOrder)
  }

  var body: some View {
    content
      // The custom hero title (below) replaces the system large title, matching
      // Library and Settings.
      .toolbar(.hidden, for: .navigationBar)
      .background(ArtworkBackdrop(url: nil))
      // Reconcile with the server on activation (no-op offline / signed out).
      .task { await flashcards.sync() }
  }

  @ViewBuilder
  private var content: some View {
    if flashcards.cards.isEmpty {
      EmptyState(
        systemImage: "rectangle.on.rectangle.angled",
        title: "No flashcards yet",
        message: "Long-press a word in a song's lyrics and tap Save to flashcards to start your deck."
      )
    } else {
      List {
        // The hero scrolls away with the list (first row), matching Library.
        header
          .listRowBackground(Color.clear)
          .listRowSeparator(.hidden)
          .listRowInsets(EdgeInsets(
            top: Spacing.l, leading: Spacing.l, bottom: Spacing.s, trailing: Spacing.l
          ))

        studyLink
          .listRowBackground(Color.clear)
          .listRowSeparator(.hidden)

        ForEach(filtered) { card in
          FlashcardDeckRow(
            card: card,
            target: target,
            showFurigana: showFurigana,
            showSourceLine: showSourceLine
          )
          .listRowBackground(Color.clear)
          .listRowSeparator(.hidden)
        }
        .onDelete(perform: deleteRows)
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
      .searchable(text: $query)
      .contentMargins(.bottom, Spacing.m, for: .scrollContent)
    }
  }

  /// Custom hero title, matching Library and Settings: `Typography.pageTitle`
  /// at the same top offset, with a card-count subtitle in Library's shape.
  private var header: some View {
    HStack(alignment: .top, spacing: Spacing.m) {
      VStack(alignment: .leading, spacing: Spacing.xs) {
        Text("Flashcards")
          .font(Typography.pageTitle)
        Text(headerSubtitle)
          .font(Typography.metadata)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
      displayMenu
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// Per-deck controls, fronted by the hero (the nav bar is hidden): display
  /// toggles (furigana ruby, captured lyric line), the browse-list sort, and a
  /// quick filter.
  private var displayMenu: some View {
    Menu {
      Toggle(isOn: $showFurigana) {
        Label("Furigana", systemImage: "characters.lowercase")
      }
      Toggle(isOn: $showSourceLine) {
        Label("Lyric line", systemImage: "text.quote")
      }

      Picker("Sort", selection: $deckSortRaw) {
        ForEach(DeckSort.allCases) { option in
          Text(option.label).tag(option.rawValue)
        }
      }

      Picker("Filter", selection: $filter) {
        Text("All cards").tag(DeckFilter.all)
        Text("Due now").tag(DeckFilter.dueNow)
        Text("Needs review").tag(DeckFilter.needsReview)
        if !songs.isEmpty {
          // Section divider plus one entry per source song in the deck.
          Divider()
          ForEach(songs, id: \.self) { title in
            Text(title).tag(DeckFilter.song(title))
          }
        }
      }
    } label: {
      Image(systemName: "textformat.size")
        .font(Typography.sectionTitle)
        .foregroundStyle(.secondary)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }
  }

  /// Hero subtitle: total card count, mirroring Library's "N songs".
  private var headerSubtitle: String {
    let count = flashcards.cards.count
    let unit = count == 1 ? "card" : "cards"
    return "\(count) \(unit)"
  }

  /// The entry into study mode, showing how many cards are due now.
  private var studyLink: some View {
    let due = flashcards.dueCards().count
    return NavigationLink {
      StudyView()
    } label: {
      HStack(spacing: Spacing.m) {
        Image(systemName: "play.circle.fill")
          .font(.system(size: 30))
          .foregroundStyle(Color("AccentColor"))
        VStack(alignment: .leading, spacing: Spacing.xs) {
          Text("Study")
            .font(Typography.sectionTitle)
          Text(due > 0 ? "\(due) due now" : "All caught up")
            .font(Typography.metadata)
            .foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
      }
      .padding(Spacing.m)
      .frame(maxWidth: .infinity)
      .background(
        RoundedRectangle(cornerRadius: Radii.lg, style: .continuous)
          .fill(Materials.contentSurface.color)
      )
    }
    .buttonStyle(.plain)
    // Sits just under the hero now, so the top inset is the tighter Spacing.s
    // (the hero supplies the Spacing.l top offset).
    .listRowInsets(EdgeInsets(
      top: Spacing.s, leading: Spacing.l, bottom: Spacing.s, trailing: Spacing.l
    ))
  }

  private func deleteRows(_ offsets: IndexSet) {
    for surface in offsets.map({ filtered[$0].surface }) {
      flashcards.remove(surface: surface)
    }
  }
}

/// One deck row: the word with its reading rendered as ruby (furigana stacked
/// above, toggleable), its meaning (or an on-demand "Show meaning" request when
/// none is stored yet), the lyric line it was captured from (toggleable), and the
/// song it came from.
private struct FlashcardDeckRow: View {
  let card: Flashcard
  let target: String
  let showFurigana: Bool
  let showSourceLine: Bool
  @Environment(FlashcardsState.self) private var flashcards

  /// The saved word as ruby cells, aligning its stored reading over the surface
  /// with the same okurigana split the lyric surface uses.
  private var surfaceTokens: [RubyToken] {
    FuriganaAnnotator.align(surface: card.surface, reading: card.reading)
  }

  private var sourceContext: String? {
    let parts = [card.sourceTitle, card.sourceArtist]
      .compactMap { $0 }
      .filter { !$0.isEmpty }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      RubyText(tokens: surfaceTokens, showFurigana: showFurigana)
      meaning
      if showSourceLine, let line = card.sourceLine, !line.isEmpty {
        RubyText(tokens: SourceLineCodec.parse(line), showFurigana: showFurigana)
          .foregroundStyle(.secondary)
          .padding(.top, Spacing.xs)
      }
      if let sourceContext {
        Text(sourceContext)
          .font(Typography.metadata)
          .foregroundStyle(.tertiary)
          .lineLimit(1)
      }
    }
    .padding(Spacing.m)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: Radii.md, style: .continuous)
        .fill(Materials.contentSurface.color)
    )
  }

  @ViewBuilder
  private var meaning: some View {
    if let meaning = card.meaning(for: target) {
      Text(meaning)
        .font(Typography.body)
    } else {
      Button("Show meaning") {
        Task { await flashcards.fetchCardContext(surface: card.surface) }
      }
      .font(Typography.metadata)
      .buttonStyle(.plain)
      .foregroundStyle(Color("AccentColor"))
    }
  }
}
