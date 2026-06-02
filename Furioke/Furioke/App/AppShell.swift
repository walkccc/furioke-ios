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
  @Environment(AuthService.self) private var auth
  @Environment(MusicState.self) private var music
  @Environment(NowPlayingState.self) private var nowPlaying
  @Environment(LibraryState.self) private var library
  @Environment(FlashcardsState.self) private var flashcards
  @Environment(YouTubePlayerController.self) private var youTube
  @Environment(PreferencesState.self) private var preferences

  /// Namespace + id pairing the mini-player's `.matchedTransitionSource` with the
  /// NowPlaying cover's `.navigationTransition(.zoom)`, so the whole platter zooms
  /// up into the full surface and shrinks back on interactive dismiss.
  @Namespace private var playerNamespace
  private let playerTransitionID = "nowPlaying"

  @State private var selection: AppTab = .library

  var body: some View {
    @Bindable var nowPlaying = nowPlaying

    return ZStack(alignment: .bottom) {
      LiquidGlassTabBar(
        selection: $selection,
        showsAccessory: music.currentTrack != nil,
        library: { LibraryView() },
        search: { SearchView(onOpenSettings: { selection = .settings }) },
        tango: { NavigationStack { TangoView() } },
        settings: { SettingsView() },
        bottomAccessory: { miniPlayer }
      )
      // The live IFrame player lives here — app-wide, not under the Now Playing
      // cover — so view-backed sources keep playing even when nothing presents Now
      // Playing (the study list's per-line play button). See `persistentVideoHost`.
      persistentVideoHost
    }
    .fullScreenCover(isPresented: $nowPlaying.isPresented) {
      nowPlayingCover
    }
    // First-launch onboarding, presented over the shell and gated by the
    // persisted completion flag. The shell stays mounted beneath, so completing
    // or skipping reveals the Library tab with no restart. At first launch no
    // track is loaded, so this never contends with the NowPlaying cover above.
    .fullScreenCover(isPresented: onboardingBinding) {
      onboardingCover
    }
    // The shared sign-in prompt. While the NowPlaying cover is up it hosts its own
    // copy (a sheet under the cover can't show), so this one is gated to when the
    // cover is down — exactly one is ever active for the single prompt flag.
    .sheet(isPresented: signInPromptBinding(whileCoverPresented: false)) {
      SignInView()
    }
    // Pull the user's reading overrides from Supabase on launch / sign-in (and
    // flush any queued local writes first), so corrections made on another device
    // or before a reinstall apply to lyrics here. Reconnects are covered separately
    // by `observeReconnect`.
    .task { await nowPlaying.syncPendingOverrides() }
    // The app's one out-of-quota toast, hosted here so any tab (the flashcard deck,
    // its browse list) raising the shared notice surfaces it over the tab content.
    // The Now Playing cover carries its own translation notice, so it sits below
    // the cover by design.
    .quotaNoticeToast()
  }

  /// The single sign-in-prompt flag (`AuthService.isSignInPromptPresented`) is
  /// hosted in two places — the shell and the NowPlaying cover — because a sheet
  /// can't present from under a `fullScreenCover`. Each host scopes itself to
  /// whether the cover is up so only one ever presents.
  private func signInPromptBinding(whileCoverPresented coverPresented: Bool) -> Binding<Bool> {
    Binding(
      get: { auth.isSignInPromptPresented && nowPlaying.isPresented == coverPresented },
      set: { newValue in if !newValue { auth.isSignInPromptPresented = false } }
    )
  }

  // MARK: Onboarding

  /// Presents the onboarding cover while onboarding hasn't been completed.
  /// Flipping the persisted flag (via complete / skip) makes the getter return
  /// false and dismisses the cover; the setter completes onboarding on any
  /// dismissal so the flag is the single source of truth.
  private var onboardingBinding: Binding<Bool> {
    Binding(
      get: { !preferences.hasCompletedOnboarding },
      set: { presented in if !presented { preferences.completeOnboarding() } }
    )
  }

  /// A cover presents in a fresh environment branch; re-inject the state the
  /// flow and its children read — `MusicState` for the provider step,
  /// `PreferencesState` for the native-language step and the gate, and
  /// `AuthService` for the optional sign-in prompt.
  private var onboardingCover: some View {
    OnboardingFlow()
      .environment(auth)
      .environment(music)
      .environment(preferences)
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
        // Translation is reserved for a permanent account; a guest gets the
        // sign-in prompt and the toggle does not flip on.
        onToggleTranslation: { if auth.requirePermanentAccount() { nowPlaying.toggleTranslation() }
        },
        furiganaLoading: nowPlaying.furiganaLoading,
        translationLoading: nowPlaying.isTranslating,
        translationNotice: nowPlaying.translationNoticeText,
        // The static error messages are catalog keys, so wrapping the runtime
        // string localizes them; provider-supplied messages fall through verbatim.
        playbackNotice: music.lastPlaybackError?.userMessage.map { LocalizedStringKey($0) },
        isSaved: track.map(library.isSaved) ?? false,
        // Saving to the library is reserved for a permanent account; a guest gets
        // the sign-in prompt instead of a write.
        onToggleSave: { if auth.requirePermanentAccount() { toggleSaved(track) } },
        onCollapse: collapse,
        onPrev: { Task { _ = await music.control(.previous) } },
        onPlayPause: togglePlayPause,
        onNext: { Task { _ = await music.control(.next) } },
        controlsDimmed: nowPlaying.editingReading != nil,
        videoSurface: { videoSurface },
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
    // A cover presents in a fresh environment branch; re-inject the players the
    // lyric surface + reading editor read. Flashcards is here too so the lyric
    // surface can mark saved words and the editor's save toggle works. Auth is
    // re-injected so the reserved-feature gate's sign-in prompt (hosted below)
    // has it.
    .environment(auth)
    .environment(music)
    .environment(nowPlaying)
    .environment(flashcards)
    .environment(youTube)
    // The cover hosts its own copy of the sign-in prompt, since a sheet can't
    // present from under a `fullScreenCover`. Scoped to when the cover is up.
    .sheet(isPresented: signInPromptBinding(whileCoverPresented: true)) {
      SignInView()
    }
  }

  /// The live IFrame player, mounted app-wide for the whole lifetime of a `.video`
  /// session — not only while the Now Playing cover is up — so playback survives
  /// without Now Playing being presented. The web view must stay in the view
  /// hierarchy to keep audio alive (a removed or zero-size web view suspends YouTube
  /// playback), so headless callers that never present Now Playing — the study
  /// deck's per-line play button — can still drive it. It's collapsed to a
  /// transparent, non-interactive 1pt sliver: the visible reading surface is the Now
  /// Playing lyrics; here the web view is purely the audio/JS host. Mounted by
  /// capability (`.video`), never by `provider == .youtube`, so it appears exactly
  /// when an active source needs it.
  @ViewBuilder
  private var persistentVideoHost: some View {
    if music.playerSurface == .video {
      YouTubePlayerView(controller: youTube)
        .frame(width: 1, height: 1)
        .opacity(0.02)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
  }

  /// The Now Playing video slot: on a hard playback failure it shows the "View on
  /// YouTube" hand-off (the in-app player can't recover). The live web view itself
  /// is *not* here — it's hosted app-wide by `persistentVideoHost` so playback
  /// doesn't depend on this cover being presented. Gated on capability (`.video`),
  /// never on `provider == .youtube`.
  @ViewBuilder
  private var videoSurface: some View {
    if music.playerSurface == .video {
      videoFallback
    }
  }

  /// "View on YouTube" fallback, shown only when in-app playback failed hard
  /// (region lock, embed disabled, removed, or a stall). Because the player is
  /// otherwise hidden, this stands on its own as a 16:9 banner above the lyrics.
  /// The watch URL is the track's own `uri`, so this stays gated on the `.video`
  /// surface above rather than naming a provider.
  @ViewBuilder
  private var videoFallback: some View {
    if let error = music.lastPlaybackError, isHardPlaybackError(error),
       let track = music.currentTrack, let url = URL(string: track.uri)
    {
      ZStack {
        Color.black.opacity(0.72)
        Link(destination: url) {
          Label("View on YouTube", systemImage: "play.rectangle.fill")
            .font(Typography.metadata)
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.s)
            .glassEffect(Materials.controlTier.glass, in: Capsule())
        }
        .buttonStyle(.plain)
      }
      .aspectRatio(16.0 / 9.0, contentMode: .fit)
      .frame(maxWidth: .infinity)
      .clipShape(RoundedRectangle(cornerRadius: Radii.md, style: .continuous))
      .padding(.horizontal, Spacing.l)
      .padding(.bottom, Spacing.m)
    }
  }

  /// Playback failures with no in-app recovery — the only ones that warrant the
  /// external hand-off.
  private func isHardPlaybackError(_ error: MusicError) -> Bool {
    switch error {
    case .unplayable, .embedDisabled, .notFound, .regionLocked, .playbackDidNotStart:
      true
    default:
      false
    }
  }

  /// The dimming scrim + floating reading editor, shown while a reading edit is
  /// open. The scrim covers the whole surface (tapping it cancels). A correctable
  /// (kanji) card is pinned to the bottom and slides up from the keyboard; a
  /// kana-only card has no keyboard, so it centers vertically and fades in. Save /
  /// Cancel route back through `NowPlayingState`.
  @ViewBuilder
  private var readingEditorOverlay: some View {
    if let edit = nowPlaying.editingReading {
      let correctable = FuriganaAnnotator.containsKanji(edit.surface)
      ZStack(alignment: correctable ? .bottom : .center) {
        DimScrim { nowPlaying.cancelEditing() }
        ReadingEditorCard(
          surface: edit.surface,
          correctable: correctable,
          initialReading: edit.reading,
          initialRemember: edit.rememberEverywhere,
          showsSaveToFlashcards: true,
          initialSaved: nowPlaying.isEditingWordSaved,
          onCancel: { nowPlaying.cancelEditing() },
          onSave: { reading, remember in
            nowPlaying.commitEditing(reading: reading, rememberEverywhere: remember)
          },
          onToggleSave: { reading in
            nowPlaying.toggleSaveCurrentWord(reading: reading)
          }
        )
        .padding(.horizontal, Spacing.l)
        .padding(.bottom, correctable ? Spacing.l : 0)
        .transition(
          correctable
            ? .move(edge: .bottom).combined(with: .opacity)
            : .opacity
        )
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

  /// Tap or drag-up on the mini-player. `present()` wraps the toggle in the snappy
  /// `Motion.sheet` curve so the zoom open finishes fast and swipe-to-dismiss arms
  /// promptly.
  private func expand() {
    nowPlaying.present()
  }

  private func collapse() {
    nowPlaying.dismiss()
  }
}
