import SwiftUI

// Composition root for the tab bar + mini-player + NowPlaying layout. Owns
// the layout seam: feature views (Library / Search / Settings) never reach into
// the chrome — they request playback via `NowPlayingState`, which drives the
// `isPresented` flag this view binds the NowPlaying cover to.
//
// NowPlaying is presented as a `.fullScreenCover` driven by
// `nowPlaying.isPresented`, with the native zoom transition
// (`.matchedTransitionSource` on the mini-player ↔ `.navigationTransition(.zoom)`
// on the cover). The whole mini-player platter zooms up into the
// surface and the system owns the interactive swipe-to-dismiss-from-anywhere, so
// there is no custom morph, drag, or expansion state machine to maintain.

struct AppShell: View {
  @Environment(MusicState.self) private var music
  @Environment(NowPlayingState.self) private var nowPlaying
  @Environment(LibraryState.self) private var library

  /// Namespace + id pairing the mini-player's `.matchedTransitionSource` with the
  /// NowPlaying cover's `.navigationTransition(.zoom)`, so the whole platter zooms
  /// up into the full surface and shrinks back on interactive dismiss.
  @Namespace private var playerNamespace
  private let playerTransitionID = "nowPlaying"

  /// Persists across launches so the onboarding hint shows at most once.
  @AppStorage("furioke.miniPlayerHintDismissed") private var hintDismissed = false

  @State private var selection: AppTab = .library

  var body: some View {
    @Bindable var nowPlaying = nowPlaying

    return ZStack(alignment: .bottom) {
      LiquidGlassTabBar(
        selection: $selection,
        library: { LibraryView() },
        search: { SearchView() },
        settings: { SettingsView() },
        bottomAccessory: { miniPlayer }
      )

      if shouldShowHint(isSheetPresented: nowPlaying.isPresented) {
        MiniPlayerHint(onClose: { dismissHint() })
          // Float above the tab bar + mini-player accessory.
          .padding(.bottom, 132)
          .padding(.horizontal, Spacing.l)
          .zIndex(1)
      }
    }
    .fullScreenCover(isPresented: $nowPlaying.isPresented) {
      nowPlayingCover
    }
    // Pull the user's reading overrides from Supabase on launch / sign-in (and
    // flush any queued local writes first), so corrections made on another device
    // or before a reinstall apply to lyrics here. Reconnects are covered separately
    // by `observeReconnect`.
    .task { await nowPlaying.syncPendingOverrides() }
  }

  // MARK: Mini-player

  @ViewBuilder
  private var miniPlayer: some View {
    if let track = music.currentTrack {
      MiniPlayer(
        title: track.title,
        artist: track.artistDisplayName,
        artworkURL: artworkURL(for: track),
        isPlaying: music.isPlaying,
        onExpand: expand,
        onPlayPause: togglePlayPause
      )
      // The whole platter is the zoom source for the NowPlaying cover.
      .matchedTransitionSource(id: playerTransitionID, in: playerNamespace)
    }
  }

  // MARK: NowPlaying sheet

  @ViewBuilder
  private var nowPlayingCover: some View {
    let track = music.currentTrack
    // The surface and the editor card are independent siblings so each manages
    // its own keyboard behaviour: the surface ignores the keyboard (the transport
    // bar stays put, with nothing to animate back down on dismiss) while the card
    // alone rides up above the keyboard.
    ZStack(alignment: .bottom) {
      NowPlayingContent(
        title: track?.title ?? "",
        artist: track?.artistDisplayName ?? "",
        artworkURL: track.flatMap(artworkURL(for:)),
        isPlaying: music.isPlaying,
        showFurigana: nowPlaying.showFurigana,
        showRomaji: nowPlaying.showRomaji,
        showTranslation: nowPlaying.showTranslation,
        onToggleFurigana: { nowPlaying.showFurigana.toggle() },
        onToggleRomaji: { nowPlaying.showRomaji.toggle() },
        onToggleTranslation: { nowPlaying.toggleTranslation() },
        furiganaLoading: nowPlaying.furiganaLoading,
        translationLoading: nowPlaying.isTranslating,
        translationNotice: nowPlaying.translationNoticeText,
        playbackNotice: music.lastPlaybackError?.userMessage,
        isSaved: track.map(library.isSaved) ?? false,
        onToggleSave: { toggleSaved(track) },
        onCollapse: collapse,
        onPrev: { Task { _ = await music.control(.previous) } },
        onPlayPause: togglePlayPause,
        onNext: { Task { _ = await music.control(.next) } },
        lyrics: { LyricsView() },
        timeline: { NowPlayingTimeline() }
      )
      // The ambient album-art wash sits behind the content as one surface.
      .background(ArtworkBackdrop(url: track.flatMap(artworkURL(for:))))
      // Don't lift the surface when the correction keyboard appears — the card
      // is the only thing that should move above the keyboard.
      .ignoresSafeArea(.keyboard, edges: .bottom)

      // The reading-correction card floats over the whole surface, docked to the
      // bottom so keyboard avoidance lifts it to sit right above the keyboard —
      // hosting it here (rather than inside the lyric column) is what closes the
      // gap, since the column's frame stops short at the transport bar.
      readingEditorOverlay
    }
    // Zoom up from / shrink back into the mini-player platter.
    .navigationTransition(.zoom(sourceID: playerTransitionID, in: playerNamespace))
    // A cover presents in a fresh environment branch; re-inject the players.
    .environment(music)
    .environment(nowPlaying)
  }

  /// The dimming scrim + floating reading editor, shown while a reading edit is
  /// open. The scrim covers the whole surface (tapping it cancels); the card is
  /// pinned to the bottom and slides up from the keyboard. Save / Cancel route
  /// back through `NowPlayingState`.
  @ViewBuilder
  private var readingEditorOverlay: some View {
    if let edit = nowPlaying.editingReading {
      ZStack(alignment: .bottom) {
        Rectangle()
          .fill(.black.opacity(0.18))
          .ignoresSafeArea()
          .contentShape(Rectangle())
          .onTapGesture { nowPlaying.cancelEditing() }
          .transition(.opacity)
        ReadingEditorCard(
          surface: edit.surface,
          initialReading: edit.reading,
          initialRemember: edit.rememberEverywhere,
          onCancel: { nowPlaying.cancelEditing() },
          onSave: { reading, remember in
            nowPlaying.commitEditing(reading: reading, rememberEverywhere: remember)
          }
        )
        .padding(.horizontal, Spacing.l)
        .padding(.bottom, Spacing.l)
        .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
  }

  // MARK: Helpers

  /// The SDK echo publishes tracks without artwork; fall back to the richer
  /// user-initiated track's artwork when ids match.
  private func artworkURL(for track: MusicTrack) -> URL? {
    if let url = track.artworkURL { return url }
    if let source = music.source, source.track.id == track.id { return source.track.artworkURL }
    return nil
  }

  private func togglePlayPause() {
    Task { _ = await music.control(music.isPlaying ? .pause : .play) }
  }

  /// NowPlaying's Save action: a library toggle — save the track, or,
  /// when it's already saved, remove it. The Now Playing surface stays open either
  /// way; the menu action no longer dismisses the sheet or switches tabs.
  private func toggleSaved(_ track: MusicTrack?) {
    guard let track else { return }
    Task {
      if library.isSaved(track) {
        await library.remove(track)
      } else {
        await library.save(track)
      }
    }
  }

  /// Tap or drag-up on the mini-player. Dismissing the hint here covers the
  /// "hint goes away once the sheet has been expanded once" rule.
  /// `present()` wraps the toggle in the snappy `Motion.sheet` curve so the zoom
  /// open finishes fast and swipe-to-dismiss arms promptly.
  private func expand() {
    dismissHint()
    nowPlaying.present()
  }

  private func collapse() {
    nowPlaying.dismiss()
  }

  // MARK: Onboarding hint

  /// Shown only the first time a track is loaded into the mini-player, and never
  /// while NowPlaying is open.
  private func shouldShowHint(isSheetPresented: Bool) -> Bool {
    music.currentTrack != nil && !hintDismissed && !isSheetPresented
  }

  private func dismissHint() {
    guard !hintDismissed else { return }
    withAnimation(Motion.ease) { hintDismissed = true }
  }
}
