import SwiftData
import SwiftUI

/// The default tab: the signed-in user's saved songs, most-recently-saved first,
/// read straight from the SwiftData cache (`SongEntity`). Rendering from the
/// local store is what lets the Library show offline; online sync and the save
/// actions that populate it land in later changes. Tapping a row plays through
/// `NowPlayingState.play(track:)` and expands the mini-player — no tab switch.
///
/// Only one provider is active at a time, and a track can only play through its
/// own provider's adapter. So the list is scoped to the active provider: tapping
/// a song from a different provider would silently fail in the adapter (the lyrics
/// would swap while the previous audio kept playing), so those rows are hidden
/// rather than shown as dead taps. With no provider selected nothing here can
/// play, so the list shows nothing at all.
struct LibraryView: View {
  @Environment(NowPlayingState.self) private var nowPlaying
  @Environment(LibraryState.self) private var library
  @Environment(MusicState.self) private var music
  @Query(sort: \SongEntity.savedAt, order: .reverse) private var songs: [SongEntity]

  /// Saved songs the active provider can actually play. With no provider active
  /// nothing here is playable, so the list is empty until one is chosen.
  private var playableSongs: [SongEntity] {
    guard let active = music.activeProvider else { return [] }
    return songs.filter { MusicProvider(rawValue: $0.provider) == active }
  }

  /// Empty-state copy: point at Settings when no provider is selected, nudge
  /// toward the matching provider when songs exist but none belong to the active
  /// one, and otherwise nudge toward saving when the library is truly empty.
  private var emptyMessage: String {
    guard let active = music.activeProvider else {
      return "Choose a provider in Settings to see your saved songs."
    }
    if !songs.isEmpty {
      return "No saved songs for \(active.displayName). Switch providers in Settings to see the rest."
    }
    return "Save a song from Search or Now Playing to read along here."
  }

  /// Seeds the ambient hero. The list is most-recent-first, so the first row is
  /// the freshest save; a nil URL lets `ArtworkBackdrop` fall back to its opaque
  /// `systemBackground` base.
  private var backdropArtworkURL: URL? {
    playableSongs.first?.artworkURL.flatMap(URL.init(string:))
  }

  /// Hero subtitle: count + active provider. In the non-empty branch a provider
  /// is always active (it's what scopes `playableSongs`), so the fallback is just
  /// belt-and-braces.
  private var headerSubtitle: String {
    let count = playableSongs.count
    let unit = count == 1 ? "song" : "songs"
    if let provider = music.activeProvider {
      return "\(count) \(unit) · \(provider.displayName)"
    }
    return "\(count) \(unit)"
  }

  var body: some View {
    content
      // The ambient album-art wash is the whole tab's backdrop, seeded from the
      // most-recent save — the same primitive Now Playing uses. Replaces the
      // stock navigation-title chrome with the custom hero below.
      .background(ArtworkBackdrop(url: backdropArtworkURL))
      // Reconcile the local mirror with the server on activation.
      // Library is the default tab, so this also covers the launch sync; a no-op
      // while offline, where the list renders straight from the cache.
      .task { await library.sync() }
  }

  @ViewBuilder
  private var content: some View {
    if playableSongs.isEmpty {
      EmptyState(
        systemImage: "music.note.list",
        title: "Your Library",
        message: emptyMessage
      )
    } else {
      List {
        // The hero scrolls away with the list (first row) so the backdrop gets
        // room to breathe at the top rather than pinning a bar over it.
        header
          .listRowBackground(Color.clear)
          .listRowSeparator(.hidden)
          .listRowInsets(EdgeInsets(
            top: Spacing.l, leading: Spacing.l, bottom: Spacing.s, trailing: Spacing.l
          ))

        ForEach(playableSongs) { song in
          Button {
            nowPlaying.play(track: song.asMusicTrack)
          } label: {
            RowItem(
              artworkURL: song.artworkURL.flatMap(URL.init(string:)),
              title: song.title,
              subtitle: song.artist
            )
          }
          .buttonStyle(.plain)
          // Clear rows so the ambient wash shows through; no dividers for a
          // cleaner read — the artwork already separates rows visually.
          .listRowBackground(Color.clear)
          .listRowSeparator(.hidden)
        }
      }
      .listStyle(.plain)
      // Drop the list's own background so the backdrop is visible behind it.
      .scrollContentBackground(.hidden)
      // The mini-player + tab bar clearance is provided by the system
      // `tabViewBottomAccessory` safe area; this is just breathing room so the
      // last row isn't flush against the glass platter.
      .contentMargins(.bottom, Spacing.m, for: .scrollContent)
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Text("Library")
        .font(Typography.pageTitle)
      Text(headerSubtitle)
        .font(Typography.metadata)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private extension SongEntity {
  /// The provider-neutral track to hand the playback seam. The persisted artwork
  /// URL seeds the mini-player so it shows immediately; the active adapter may
  /// still re-resolve it (Spotify via its Web API) after `playTrack`.
  var asMusicTrack: MusicTrack {
    let resolvedProvider = MusicProvider(rawValue: provider) ?? .spotify
    return MusicTrack(
      provider: resolvedProvider,
      providerTrackID: providerTrackID,
      uri: resolvedProvider.playbackURI(forTrackID: providerTrackID),
      title: title,
      artists: artist.isEmpty ? [] : [artist],
      album: album,
      durationMs: durationMs,
      artworkURL: artworkURL.flatMap(URL.init(string:))
    )
  }
}
