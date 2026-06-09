import SwiftUI

/// A play affordance that sits at the start of a saved card's captured lyric line.
/// The button is **always shown** wherever the line is rendered — a persistent
/// affordance, not a conditional one. Tapping plays *just* that line: it seeks to
/// the line's start and pauses at its end, never playing from the song's start and
/// never presenting Now Playing. If the card's source song isn't the active track,
/// it starts it first — switching the active provider to the card's when it differs,
/// then connecting if needed (`select` + `showUserInitiated` + `playTrack`, the
/// headless half of the Library tap, minus the surface). A card whose provider has
/// no adapter on this device is inert. It never changes card state.
///
/// Shared by the study deck (`TangoView`, inline on the line of the back face and
/// the Cloze front) and the browse list (`TangoListView`, on a card's expanded
/// citation).
struct LinePlayButton: View {
  let card: Flashcard
  var size: CGFloat = 24
  var padding: CGFloat = 0

  @Environment(MusicState.self) private var music
  @Environment(NowPlayingState.self) private var nowPlaying

  var body: some View {
    Button {
      playSourceLine()
    } label: {
      Image(systemName: "play.circle.fill")
        .font(.system(size: size))
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(Color.accentColor)
        .padding(padding)
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Play this line")
  }

  /// Play the saved word's line. When its song is already the active track, just
  /// play the line. Otherwise start that song first — switching the active provider
  /// to the card's when it differs — then play the line. A card whose provider has
  /// no adapter on this device is inert. A card with no captured track reference
  /// falls back to the line only when its song already happens to be active.
  private func playSourceLine() {
    guard card.sourceLineStartMs != nil else { return }
    if let sourceTrack {
      if music.currentTrack?.id == sourceTrack.id {
        playLine(starting: nil)
      } else if music.availableProviders.contains(sourceTrack.provider) {
        // Start it, switching to the card's provider first if it isn't active.
        playLine(starting: sourceTrack)
      }
      // Card's provider has no adapter on this device: inert.
    } else if isSourceTrackActive {
      playLine(starting: nil)
    }
  }

  /// Play *just* the line: optionally start `track` first — switching providers if
  /// needed, without presenting Now Playing — then seek to the line's start, play,
  /// and pause at its end. The end
  /// is the captured next-line time (so it works for a freshly started song whose
  /// lyrics aren't loaded), falling back to the active track's loaded lines for an
  /// older card. The pause fires only if the same track is still current.
  private func playLine(starting track: MusicTrack?) {
    guard let startMs = card.sourceLineStartMs else { return }
    let endMs = lineEndMs(startMs: startMs)
    Task {
      if let track {
        // Switch the active provider to the card's first when it differs: `select`
        // tears the old adapter down and clears playback state (so it must precede
        // `showUserInitiated`), leaving the new one disconnected; it's a no-op when
        // already active. Then headless-start (no `present()`) — `playTrack`
        // re-establishes the session, connecting the provider if needed.
        if track.provider != music.activeProvider {
          await music.select(track.provider)
        }
        music.showUserInitiated(track)
        _ = await music.playTrack(track)
      }
      _ = await music.control(.seek(positionMs: startMs))
      _ = await music.control(.play)
      let playingID = music.currentTrack?.id
      guard let endMs, endMs > startMs else { return } // last line: play on.
      try? await Task.sleep(for: .milliseconds(endMs - startMs))
      guard music.currentTrack?.id == playingID else { return }
      _ = await music.control(.pause)
    }
  }

  /// The card's captured source song as a playable track, or nil when no track
  /// reference was captured (nothing was playing at save, or an older/web card).
  /// Title/artist seed the mini-player; artwork is seeded from any id-derivable
  /// thumbnail (YouTube) so the mini-player shows cover art immediately rather than
  /// a blank placeholder; the adapter re-resolves duration (and richer artwork).
  private var sourceTrack: MusicTrack? {
    guard let providerRaw = card.sourceProvider,
          let provider = MusicProvider(rawValue: providerRaw),
          let trackID = card.sourceTrackID, !trackID.isEmpty
    else { return nil }
    return MusicTrack(
      provider: provider,
      providerTrackID: trackID,
      uri: provider.playbackURI(forTrackID: trackID),
      title: card.sourceTitle ?? "",
      artists: card.sourceArtist.map { [$0] } ?? [],
      album: nil,
      durationMs: 0,
      artworkURL: provider.artworkURL(forTrackID: trackID)
    )
  }

  /// True when the card's captured source song matches the active track. Matched
  /// leniently (trimmed, case-insensitive) — title must match, and the artist too
  /// when the card recorded one. Used only for the no-track-reference fallback.
  private var isSourceTrackActive: Bool {
    guard let track = music.currentTrack,
          let title = card.sourceTitle, normalized(title) == normalized(track.title)
    else { return false }
    if let artist = card.sourceArtist, !normalized(artist).isEmpty,
       normalized(artist) != normalized(track.artistDisplayName)
    {
      return false
    }
    return true
  }

  private func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  /// The saved line's end (ms): the captured next-line time, or — for an older
  /// card without it whose song is the active track — the first loaded line after
  /// `startMs`. Nil when it's the last line, so the caller lets playback continue.
  private func lineEndMs(startMs: Int) -> Int? {
    card.sourceLineEndMs
      ?? nowPlaying.lines.compactMap(\.timeMs).filter { $0 > startMs }.min()
  }
}

/// A `LinePlayButton` dropped onto — and **vertically centred on** — the surface row
/// of a ruby line, so it sits on the lyric rather than below it. It reserves a blank
/// furigana row above the button (matching the ruby stacked on top of the line) and
/// then centres the button within the surface row's own height, measured from the
/// passed `surfaceFont`. The button overflows that row symmetrically, which is fine —
/// it's the leading element with nothing beside it there. Place it as the leading
/// element of an `HStack(alignment: .top)` beside a `RubyText`, passing the same
/// `surfaceFont` / `furiganaFont` that text uses so the rows match. When the line
/// wraps across rows the button stays on the first row. Prefer `PlayableSourceLine`,
/// which pairs this with the line and any caption; shared by the study card (back
/// face + Cloze front) and the browse list's citation.
struct SurfaceAlignedPlayButton: View {
  let card: Flashcard
  var size: CGFloat = 24
  var surfaceFont: Font = Typography.body
  var furiganaFont: Font = Typography.furigana

  /// The surface row's height for the current font + Dynamic Type, measured from a
  /// hidden sample so the button can be centred on it. Zero until first measured.
  @State private var surfaceHeight: CGFloat = 0

  var body: some View {
    VStack(spacing: 0) {
      // The reserved furigana row: matches the ruby's stacked reading height (0
      // spacing, as in `RubyCell`), so the button below lands on the surface row.
      Text(" ").font(furiganaFont).hidden()
      // Centre the button within the surface row's height, so its glyph lands on the
      // lyric's centre instead of hanging below it. Until measured, fall back to the
      // button's natural height.
      LinePlayButton(card: card, size: size, padding: 0)
        .frame(height: surfaceHeight > 0 ? surfaceHeight : nil)
    }
    .background(alignment: .top) {
      Text(" ")
        .font(surfaceFont)
        .hidden()
        .background {
          GeometryReader { proxy in
            Color.clear.preference(key: SurfaceHeightKey.self, value: proxy.size.height)
          }
        }
    }
    .onPreferenceChange(SurfaceHeightKey.self) { surfaceHeight = $0 }
  }
}

/// Carries the measured surface-row height out of the hidden sample text.
private struct SurfaceHeightKey: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = max(value, nextValue())
  }
}

/// A captured lyric line rendered as ruby with a leading play button centred on the
/// line's surface row, plus optional caption content (a translation, a citation)
/// stacked beneath the line. The single layout behind the study card's back face and
/// Cloze front and the browse list's citation, so the play button sits on the lyric
/// the same way everywhere. When the line wraps, the button stays on the first row.
struct PlayableSourceLine<Caption: View>: View {
  let card: Flashcard
  let tokens: [RubyToken]
  var highlightWord: String?
  var buttonSize: CGFloat = 24
  var spacing: CGFloat = Spacing.m
  var surfaceFont: Font = Typography.body
  var furiganaFont: Font = Typography.furigana
  var furiganaStyle: AnyShapeStyle = .init(.primary.opacity(0.7))
  @ViewBuilder var caption: () -> Caption

  var body: some View {
    HStack(alignment: .top, spacing: spacing) {
      SurfaceAlignedPlayButton(
        card: card,
        size: buttonSize,
        surfaceFont: surfaceFont,
        furiganaFont: furiganaFont
      )
      VStack(alignment: .leading, spacing: Spacing.xs) {
        RubyText(
          tokens: tokens,
          showFurigana: true,
          highlightWord: highlightWord,
          wraps: true,
          surfaceFont: surfaceFont,
          furiganaFont: furiganaFont,
          furiganaStyle: furiganaStyle
        )
        caption()
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
