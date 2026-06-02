import SwiftUI

/// The browse list, reached as the "browse" destination from the 単語 tab's swipe
/// deck: every saved card as a row (word ruby with its meaning beneath) and its
/// captured source citation. Every row uses the **same** layout (`TangoRow`) — there's
/// no expander — and a toolbar controls what that layout shows (the source line, the
/// translations, the song citation). The list is always newest-first; there is no
/// re-ordering. When translations are shown a row surfaces any it's missing as a
/// tap-to-translate affordance — fetched only on an explicit tap (with a placeholder
/// while one lands and the shared out-of-quota notice if the daily limit is hit),
/// never on appearance, so browsing the list never spends quota. Study-mode
/// sequencing is unaffected — it always follows the spaced-repetition schedule.
struct TangoListView: View {
  @Environment(FlashcardsState.self) private var flashcards
  @Environment(PreferencesState.self) private var preferences
  @Environment(MusicState.self) private var music

  @State private var query = ""
  /// What each row shows, toggled from the toolbar. Persisted so the learner's
  /// preference holds across visits.
  @AppStorage("furioke.tango.showSource") private var showSource = true
  @AppStorage("furioke.tango.showTranslation") private var showTranslation = true
  @AppStorage("furioke.tango.showCitation") private var showCitation = true
  @State private var songFilter: String?

  var body: some View {
    content
      .background(ArtworkBackdrop(url: music.currentTrack?.artworkURL))
      .navigationTitle("List")
      .navigationBarTitleDisplayMode(.inline)
      .searchable(text: $query)
      .toolbar { ToolbarItem(placement: .topBarTrailing) { viewOptionsMenu } }
      .onAppear { flashcards.reload() }
      .task { await flashcards.sync() }
  }

  /// The toolbar control for what the rows show: the source line, the translations,
  /// and the song citation. Each is an independent toggle.
  private var viewOptionsMenu: some View {
    Menu {
      Toggle(isOn: $showSource) {
        Label("Show source line", systemImage: "text.quote")
      }
      Toggle(isOn: $showTranslation) {
        Label("Show translation", systemImage: "translate")
      }
      Toggle(isOn: $showCitation) {
        Label("Show citation", systemImage: "music.note.list")
      }
    } label: {
      Label("View options", systemImage: "ellipsis")
    }
  }

  @ViewBuilder
  private var content: some View {
    if !flashcards.isSignedIn {
      EmptyState(
        systemImage: "person.crop.circle.badge.questionmark",
        title: "Sign In Required",
        message: "Flashcards are saved per account. Sign in to see your deck."
      )
    } else if flashcards.deck.isEmpty {
      EmptyState(
        systemImage: "rectangle.stack.badge.plus",
        title: "No Cards Yet",
        message: "Long-press a word in Now Playing and save it to flashcards. Your saved words appear here."
      )
    } else {
      let rows = visibleCards
      if rows.isEmpty {
        EmptyState(
          systemImage: "magnifyingglass",
          title: "No Matches",
          message: "No cards match your search."
        )
      } else {
        deckList(rows)
      }
    }
  }

  /// The deck as glass cards: a plain list with its own background and separators
  /// hidden so each `TangoRow`'s glass floats over the artwork backdrop laid down in
  /// `body`. Row insets give the cards breathing room and a gutter between them.
  private func deckList(_ rows: [Flashcard]) -> some View {
    List {
      ForEach(rows) { card in
        TangoRow(
          card: card,
          target: preferences.translationTarget,
          showSource: showSource,
          showTranslation: showTranslation,
          showCitation: showCitation
        )
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(
          top: Spacing.xs,
          leading: Spacing.l,
          bottom: Spacing.xs,
          trailing: Spacing.l
        ))
        .swipeActions(edge: .trailing) {
          Button(role: .destructive) {
            Task { await flashcards.remove(surface: card.surface) }
          } label: {
            Label("Delete", systemImage: "trash")
          }
        }
      }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
  }

  // MARK: Filtering

  /// The deck after search and filters, in the cache's natural newest-first order.
  /// Search is language-aware (surface, reading, or the active-language gloss).
  private var visibleCards: [Flashcard] {
    let target = preferences.translationTarget
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return flashcards.deck.filter { card in
      (songFilter == nil || card.sourceTitle == songFilter)
        && matchesQuery(card, trimmed, target: target)
    }
  }

  private func matchesQuery(_ card: Flashcard, _ query: String, target: String) -> Bool {
    guard !query.isEmpty else { return true }
    if card.surface.lowercased().contains(query) { return true }
    if card.reading.lowercased().contains(query) { return true }
    if let meaning = glossFor(card.meaning, target),
       meaning.lowercased().contains(query) { return true }
    return false
  }
}
