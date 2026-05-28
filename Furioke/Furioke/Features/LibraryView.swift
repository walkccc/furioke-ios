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

  var body: some View {
    NavigationStack {
      Group {
        if playableSongs.isEmpty {
          EmptyState(
            systemImage: "music.note.list",
            title: "Your Library",
            message: emptyMessage
          )
        } else {
          List(playableSongs) { song in
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
          }
          .listStyle(.plain)
        }
      }
      .navigationTitle("Library")
      // Reconcile the local mirror with the server on activation.
      // Library is the default tab, so this also covers the launch sync; a no-op
      // while offline, where the list renders straight from the cache.
      .task { await library.sync() }
    }
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
