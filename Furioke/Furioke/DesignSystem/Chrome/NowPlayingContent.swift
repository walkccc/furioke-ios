import SwiftUI

// Inner body of the NowPlaying surface, laid out lyrics-first: a compact track header
// (small thumbnail + title / artist), the injected lyric column
// filling the whole middle, and a floating glass control bar (scrubber +
// transport) docked at the bottom. The album art is deliberately small here —
// it is *presented* as a thumbnail and washed across the backdrop, never a hero
// block — because reading along is the surface's purpose.
//
// Display parameters are driven by `AppShell` from `MusicState`; the lyric
// column is injected as a feature view so the Chrome layer stays
// feature-agnostic.

struct NowPlayingContent<Lyrics: View, Timeline: View>: View {
  let title: String
  let artist: String
  let artworkURL: URL?
  let isPlaying: Bool
  let showFurigana: Bool
  let showRomaji: Bool
  let showTranslation: Bool
  let onToggleFurigana: () -> Void
  let onToggleRomaji: () -> Void
  let onToggleTranslation: () -> Void
  /// Furigana is being computed in the background (a cold kuromoji build can take
  /// a few seconds). Drives a progress toast — shown only while `showFurigana` is
  /// on, since the readings are computed regardless but there's nothing to wait
  /// for visually when they're hidden.
  let furiganaLoading: Bool
  /// A whole-body translation is being fetched. Drives a progress toast while the
  /// translation toggle is on and the request is in flight.
  let translationLoading: Bool
  /// A transient banner for a failed/offline translation attempt; nil when there's
  /// nothing to surface.
  let translationNotice: String?
  /// A transient banner for a playback/connection failure (e.g. a Spotify reconnect
  /// that couldn't complete); nil when there's nothing to surface. Lets a dropped
  /// session announce itself instead of leaving the transport silently dead.
  let playbackNotice: String?
  /// Whether the current track is already in the user's library — drives the
  /// Save/Saved state of the save action.
  let isSaved: Bool
  /// Toggle the current track in the user's library: save it, or — when already
  /// saved — remove it. The Now Playing surface stays open either way.
  let onToggleSave: () -> Void
  let onCollapse: () -> Void
  let onPrev: () -> Void
  let onPlayPause: () -> Void
  let onNext: () -> Void
  @ViewBuilder let lyrics: () -> Lyrics
  /// The drag-to-seek scrubber and time labels, injected as a feature view so
  /// the high-frequency position ticker stays out of this surface's body and
  /// can't re-render the controls (e.g. the open options menu) on every tick.
  @ViewBuilder let timeline: () -> Timeline

  /// A brief confirmation shown when the current track becomes saved, wherever the
  /// save was triggered from.
  @State private var savedConfirmed = false

  var body: some View {
    VStack(spacing: 0) {
      topChrome
      lyrics()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .mask(edgeFade)
      controlBar
    }
    .overlay(alignment: .top) { topBanners }
    .overlay(alignment: .bottom) { savedToast }
    .onChange(of: isSaved) { _, saved in
      if saved { withAnimation(Motion.pop) { savedConfirmed = true } }
    }
  }

  /// The top-docked transient toasts, stacked so progress and notice toasts can
  /// coexist without overlapping. All share the one `Toast` style. Animated as a
  /// group since their source state mutates outside an explicit `withAnimation`.
  @ViewBuilder
  private var topBanners: some View {
    VStack(spacing: Spacing.s) {
      // Computed even when hidden, so only surface progress while furigana is on.
      if furiganaLoading, showFurigana {
        Toast(text: "Adding furigana…", kind: .progress)
          .transition(.move(edge: .top).combined(with: .opacity))
      }
      if translationLoading {
        Toast(text: "Translating…", kind: .progress)
          .transition(.move(edge: .top).combined(with: .opacity))
      }
      if let translationNotice {
        Toast(text: translationNotice, kind: .icon("globe"))
          .transition(.move(edge: .top).combined(with: .opacity))
      }
      if let playbackNotice {
        Toast(text: playbackNotice, kind: .icon("exclamationmark.triangle.fill"))
          .transition(.move(edge: .top).combined(with: .opacity))
      }
    }
    .padding(.top, Spacing.xxl)
    .animation(Motion.ease, value: furiganaLoading)
    .animation(Motion.ease, value: translationLoading)
    .animation(Motion.ease, value: translationNotice)
    .animation(Motion.ease, value: playbackNotice)
  }

  /// The non-scrolling top zone: a centered grabber handle, then the track header
  /// (which carries the display controls on the artwork line). Interactive
  /// dismissal is owned by the `.fullScreenCover`'s zoom transition — a swipe-down
  /// from anywhere shrinks the surface back into the mini-player — so the grabber
  /// is purely a visual handle plus a tap/VoiceOver dismiss affordance.
  private var topChrome: some View {
    VStack(spacing: 0) {
      grabber
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.s)
      header
    }
  }

  /// A visual handle at the top of the surface. The swipe-to-dismiss itself is the
  /// cover's native zoom gesture (works from anywhere); this also takes a tap and a
  /// VoiceOver activation to collapse, so the dismiss is reachable non-visually.
  private var grabber: some View {
    Capsule(style: .continuous)
      .fill(.secondary)
      .opacity(0.6)
      .frame(width: 36, height: 5)
      .frame(width: 120, height: 36)
      .contentShape(Rectangle())
      .onTapGesture { onCollapse() }
      .accessibilityElement()
      .accessibilityLabel("Now Playing")
      .accessibilityHint("Activate to collapse")
      .accessibilityAddTraits(.isButton)
      .accessibilityAction { onCollapse() }
  }

  /// The display controls that sit on the artwork line, trailing: あ toggles
  /// furigana, the ellipsis opens the rōmaji / translation / save menu. Each
  /// wears a circular glass disc — quiet over the backdrop when off, brightened
  /// with a white tint when on so an active toggle reads as a lit-up circle.
  /// Wrapped in a `GlassEffectContainer` so the two discs blend as a pair.
  private var displayControls: some View {
    GlassEffectContainer(spacing: Spacing.s) {
      HStack(spacing: Spacing.s) {
        furiganaToggle
        optionsMenu
      }
    }
  }

  /// あ — toggles the furigana readings above the kanji. The disc brightens and
  /// the glyph goes solid white when on; quiet otherwise.
  private var furiganaToggle: some View {
    Button(action: onToggleFurigana) {
      Text("あ")
        .font(.system(size: 19, weight: .semibold, design: .rounded))
        .foregroundStyle(showFurigana ? .primary : .secondary)
        .frame(width: 40, height: 40)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .glassEffect(discGlass(isActive: showFurigana), in: Circle())
    .accessibilityLabel("Furigana")
    .accessibilityValue(showFurigana ? "On" : "Off")
  }

  /// The ellipsis menu: rōmaji and translation as checkable toggles, plus the
  /// save/remove-from-library action.
  private var optionsMenu: some View {
    Menu {
      Toggle(isOn: toggleBinding(showRomaji, onToggleRomaji)) {
        Label("Show rōmaji", systemImage: "textformat.alt")
      }
      Toggle(isOn: toggleBinding(showTranslation, onToggleTranslation)) {
        Label("Show translation", systemImage: "globe")
      }
      Divider()
      Button(action: onToggleSave) {
        Label(
          isSaved ? "Remove from Library" : "Save to Library",
          systemImage: isSaved ? "minus.circle" : "plus.circle"
        )
      }
    } label: {
      Image(systemName: "ellipsis")
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(showRomaji || showTranslation ? .primary : .secondary)
        .frame(width: 40, height: 40)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .glassEffect(discGlass(isActive: showRomaji || showTranslation), in: Circle())
    .accessibilityLabel("More options")
  }

  /// Glass for a display-control disc: the interactive control-tier glass,
  /// tinted brighter when the control is active so its "on" state reads as a
  /// lit-up circle rather than a colour change on the glyph alone.
  private func discGlass(isActive: Bool) -> Glass {
    isActive
      ? Materials.controlTier.glass.tint(.white.opacity(0.5))
      : Materials.controlTier.glass
  }

  /// A menu `Toggle` reads/writes through here so it shows a checkmark while the
  /// real state lives in `NowPlayingState` (via the injected toggle closures).
  private func toggleBinding(_ value: Bool, _ toggle: @escaping () -> Void) -> Binding<Bool> {
    Binding(get: { value }, set: { _ in toggle() })
  }

  @ViewBuilder
  private var savedToast: some View {
    if savedConfirmed {
      Toast(text: "Saved to Library", kind: .icon("checkmark.circle.fill"))
        .padding(.bottom, 120)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .task(id: savedConfirmed) {
          try? await Task.sleep(nanoseconds: 1_600_000_000)
          withAnimation(Motion.ease) { savedConfirmed = false }
        }
    }
  }

  /// A vertical scrim that the lyric column is masked against: fully opaque
  /// through the reading zone, dissolving to clear at the top and bottom. Lines
  /// then *fade* into the header and control bar as they scroll past, instead of
  /// being sliced off at a hard edge.
  private var edgeFade: some View {
    // Feather ~9% of the column at each end — long enough to read as a soft
    // dissolve, short enough to leave the reading zone fully lit.
    let fade = 0.09
    return LinearGradient(
      stops: [
        .init(color: .clear, location: 0),
        .init(color: .black, location: fade),
        .init(color: .black, location: 1 - fade),
        .init(color: .clear, location: 1),
      ],
      startPoint: .top,
      endPoint: .bottom
    )
  }

  // MARK: Header

  private var header: some View {
    VStack(alignment: .leading, spacing: Spacing.m) {
      HStack(spacing: Spacing.m) {
        artwork
        VStack(alignment: .leading, spacing: 2) {
          Text(title.isEmpty ? "Not playing" : title)
            .font(Typography.sectionTitle)
            .lineLimit(1)
          Text(artist)
            .font(Typography.metadata)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        Spacer(minLength: Spacing.s)
        // Center-aligned in the HStack, so the controls sit on the artwork's
        // vertical midline.
        displayControls
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, Spacing.l)
    .padding(.top, Spacing.l)
    .padding(.bottom, Spacing.l)
  }

  private var artwork: some View {
    let shape: RoundedRectangle = .init(cornerRadius: Radii.md, style: .continuous)
    return CachedArtworkImage(url: artworkURL) { image in
      image.resizable().scaledToFill()
    } placeholder: {
      shape.fill(.quaternary)
    }
    .frame(width: 56, height: 56)
    .clipShape(shape)
  }

  // MARK: Control bar

  /// No card, no border: the bar sits flat on the backdrop's bottom scrim so it
  /// reads as one continuous field with the lyrics above. Glass is pulled in
  /// from the whole bar onto the transport buttons alone — they are the only
  /// thing that should feel raised — while the time labels tuck in tight under
  /// the timeline as quiet, secondary annotation.
  private var controlBar: some View {
    VStack {
      timeline()
      GlassEffectContainer(spacing: Spacing.l) {
        HStack(spacing: Spacing.xl) {
          glassTransport(.previous, glyphSize: 18, diameter: 52, action: onPrev)
          glassTransport(
            isPlaying ? .pause : .play,
            glyphSize: 26,
            diameter: 68,
            action: onPlayPause
          )
          glassTransport(.next, glyphSize: 18, diameter: 52, action: onNext)
        }
      }
    }
    .padding(.horizontal, Spacing.xl)
  }

  /// A transport control wearing an interactive glass disc — raised and
  /// refractive against the flat bar, sized larger for the play/pause hub.
  private func glassTransport(
    _ kind: TransportButton.Kind,
    glyphSize: CGFloat,
    diameter: CGFloat,
    action: @escaping () -> Void
  ) -> some View {
    TransportButton(kind, action: action)
      .font(.system(size: glyphSize))
      .frame(width: diameter, height: diameter)
      .glassEffect(Materials.controlTier.glass, in: Circle())
  }
}
