import SwiftUI

/// Search the active connected provider's catalog and tap a result to play.
/// Input is debounced ~300ms so a typing user produces at most one request after
/// they pause; clearing the field empties the results immediately. Tapping a
/// result routes through `NowPlayingState.play(track:)` — no tab switch.
struct SearchView: View {
  @Environment(MusicState.self) private var music
  @Environment(NowPlayingState.self) private var nowPlaying
  @Environment(LibraryState.self) private var library

  @State private var query = ""
  @State private var results: [MusicTrack] = []
  @State private var phase: Phase = .idle
  @FocusState private var searchFocused: Bool

  /// Recent search terms, newest first, persisted across launches. A single-line
  /// search field can't contain newlines, so a newline-joined string is a safe,
  /// dependency-free encoding for `@AppStorage`.
  @AppStorage("furioke.recentSearches") private var recentSearchesRaw = ""

  private enum Phase: Equatable {
    case idle
    case searching
    case empty
    case results
    case failed(String)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Rounded hero title at the same top offset as Library and Settings. The
      // search field moves into the content just below it (a custom glass field),
      // so there's no navigation-bar search field pushing the title down.
      Text("Search")
        .font(Typography.pageTitle)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.l)
        .padding(.top, Spacing.l)
        .padding(.bottom, Spacing.s)

      searchField
        .padding(.horizontal, Spacing.l)
        .padding(.bottom, Spacing.s)

      content
    }
    // `.task(id:)` re-runs and cancels the prior task on every keystroke, so the
    // 300ms sleep only elapses once the user pauses — the debounce. An empty
    // field clears results without scheduling a request.
    .task(id: query) { await debouncedSearch() }
  }

  /// Custom glass search field, replacing `.searchable` so the rounded title can
  /// sit at the top like the other tabs. Wears `chromeGlass` per the design
  /// system's search-field rule; disabled until a provider is connected.
  private var searchField: some View {
    HStack(spacing: Spacing.s) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)
      TextField(
        "Songs on \(music.activeProvider?.displayName ?? "your music")",
        text: $query
      )
      .textInputAutocapitalization(.never)
      .autocorrectionDisabled()
      .submitLabel(.search)
      .focused($searchFocused)
      .onSubmit { addRecentSearch(query) }
      if !query.isEmpty {
        Button {
          query = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear search")
      }
    }
    .font(Typography.body)
    .padding(.horizontal, Spacing.m)
    .padding(.vertical, Spacing.s)
    .glassEffect(Materials.chromeGlass.glass, in: Capsule())
    .disabled(!music.isConnected)
  }

  @ViewBuilder
  private var content: some View {
    if !music.isConnected {
      EmptyState(
        systemImage: "music.note",
        title: music.activeProvider.map { "Connect \($0.displayName)" } ?? "Connect a provider",
        message: "Connect a provider in Settings to search and play songs."
      )
    } else {
      switch phase {
      case .idle:
        if recentSearches.isEmpty {
          EmptyState(
            systemImage: "magnifyingglass",
            title: "Search \(music.activeProvider?.displayName ?? "your music")",
            message: "Find a song to play and read along with furigana."
          )
        } else {
          recentSearchesList
        }
      case .searching:
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      case .empty:
        EmptyState(
          systemImage: "magnifyingglass",
          title: "No results",
          message: "Try a different search."
        )
      case .results:
        List(results) { track in
          Button {
            // The query that surfaced a played result is a meaningful search —
            // record it and drop the keyboard before the player expands.
            addRecentSearch(query)
            searchFocused = false
            nowPlaying.play(track: track)
          } label: {
            RowItem(
              artworkURL: track.artworkURL,
              title: track.title,
              subtitle: track.artistDisplayName
            ) {
              SaveButton(isSaved: library.isSaved(track)) {
                Task { await library.save(track) }
              }
            }
          }
          .buttonStyle(.plain)
          // Match Library: no dividers — the artwork separates rows visually.
          .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
      case let .failed(message):
        EmptyState(
          systemImage: "exclamationmark.triangle",
          title: "Search failed",
          message: message
        )
      }
    }
  }

  /// Idle-state list of recent searches: tap to re-run, swipe to remove one, or
  /// clear them all from the section header.
  private var recentSearchesList: some View {
    List {
      Section {
        ForEach(recentSearches, id: \.self) { term in
          Button {
            query = term
          } label: {
            Label(term, systemImage: "clock.arrow.circlepath")
              .font(Typography.body)
          }
          .buttonStyle(.plain)
          .listRowSeparator(.hidden)
          .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
              removeRecentSearch(term)
            } label: {
              Label("Remove", systemImage: "trash")
            }
          }
        }
      } header: {
        HStack {
          Text("Recent")
          Spacer()
          Button("Clear") { clearRecentSearches() }
            .font(Typography.metadata)
        }
      }
    }
    .listStyle(.plain)
  }

  // MARK: Recent searches

  private var recentSearches: [String] {
    recentSearchesRaw.split(separator: "\n").map(String.init)
  }

  /// Record a term as the most recent search: trimmed, case-insensitively
  /// de-duplicated, newest first, capped at 8.
  private func addRecentSearch(_ term: String) {
    let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    var list = recentSearches.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
    list.insert(trimmed, at: 0)
    recentSearchesRaw = list.prefix(8).joined(separator: "\n")
  }

  private func removeRecentSearch(_ term: String) {
    recentSearchesRaw = recentSearches.filter { $0 != term }.joined(separator: "\n")
  }

  private func clearRecentSearches() {
    recentSearchesRaw = ""
  }

  private func debouncedSearch() async {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      results = []
      phase = .idle
      return
    }
    // A fresh keystroke cancels this task during the sleep, coalescing a burst of
    // typing into a single request once the user stops for ~300ms.
    try? await Task.sleep(for: .milliseconds(300))
    guard !Task.isCancelled else { return }

    phase = .searching
    switch await music.search(trimmed) {
    case let .success(tracks):
      guard !Task.isCancelled else { return }
      results = tracks
      phase = tracks.isEmpty ? .empty : .results
    case let .failure(error):
      guard !Task.isCancelled else { return }
      phase = .failed(error.userMessage ?? "Something went wrong.")
    }
  }
}
