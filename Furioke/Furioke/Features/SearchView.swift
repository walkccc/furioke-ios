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

  private enum Phase: Equatable {
    case idle
    case searching
    case empty
    case results
    case failed(String)
  }

  var body: some View {
    NavigationStack {
      content
        .navigationTitle("Search")
        .searchable(
          text: $query,
          prompt: "Songs on \(music.activeProvider?.displayName ?? "your music")"
        )
        // `.task(id:)` re-runs and cancels the prior task on every keystroke, so
        // the 300ms sleep only elapses once the user pauses — the debounce. An
        // empty field clears results without scheduling a request.
        .task(id: query) { await debouncedSearch() }
    }
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
        EmptyState(
          systemImage: "magnifyingglass",
          title: "Search \(music.activeProvider?.displayName ?? "your music")",
          message: "Find a song to play and read along with furigana."
        )
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
