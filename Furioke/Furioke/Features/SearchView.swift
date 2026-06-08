import SwiftUI

/// Search the active connected provider's catalog and tap a result to play.
/// A request fires only when the user submits the field (Search key), so typing
/// produces no API calls; clearing the field empties the results immediately.
/// Tapping a result routes through `NowPlayingState.play(track:)` — no tab switch.
struct SearchView: View {
  /// Switch to the Settings tab. The disconnected empty state and the search bar
  /// itself route here, so a tap always leads somewhere a provider can be
  /// connected rather than sitting dead.
  var onOpenSettings: () -> Void = {}

  @Environment(MusicState.self) private var music
  @Environment(NowPlayingState.self) private var nowPlaying
  @Environment(LibraryState.self) private var library
  @Environment(AuthService.self) private var auth

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
      PageTitle(title: "Search")

      // No provider connected means nothing to search, so the field is hidden
      // entirely rather than shown dead — the empty state below carries the
      // call to connect one.
      if music.isConnected {
        searchField
          .padding(.horizontal, Spacing.l)
          .padding(.bottom, Spacing.s)
      }

      content
    }
    // Emptying the field resets to the idle state without firing a request; an
    // actual search only happens on submit (see the field's `.onSubmit`).
    .onChange(of: query) { _, newValue in
      if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        results = []
        phase = .idle
      }
    }
  }

  /// Custom glass search field, replacing `.searchable` so the rounded title can
  /// sit at the top like the other tabs. Wears `chromeGlass` per the design
  /// system's search-field rule. Only shown once a provider is connected.
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
      .onSubmit {
        addRecentSearch(query)
        Task { await runSearch() }
      }
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
  }

  /// Primary call-to-action on the disconnected empty state: routes to Settings,
  /// where a provider gets connected.
  private var openSettingsButton: some View {
    Button(action: onOpenSettings) {
      Label("Open Settings", systemImage: "gearshape")
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
    }
    .buttonStyle(.glassProminent)
  }

  @ViewBuilder
  private var content: some View {
    if !music.isConnected {
      EmptyState(
        systemImage: "music.note",
        title: "Connect a music provider",
        message: "Connect a music provider in Settings to search and play songs."
      ) { openSettingsButton }
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
                // Saving to the library is reserved for a permanent account; a
                // guest gets the sign-in prompt instead of a write.
                guard auth.requirePermanentAccount() else { return }
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
          // Static error messages are catalog keys; provider strings fall through.
          message: LocalizedStringKey(message)
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
            addRecentSearch(term)
            searchFocused = false
            Task { await runSearch() }
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
