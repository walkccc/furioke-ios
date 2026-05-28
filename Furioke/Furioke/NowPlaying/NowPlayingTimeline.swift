import SwiftUI

/// The playback timeline for the NowPlaying surface: the drag-to-seek scrubber
/// with the elapsed / remaining time labels tucked beneath it.
///
/// Like `LyricsView`, this reads the live `MusicState.positionMs` from the
/// environment itself rather than receiving it threaded down from `AppShell`.
/// That keeps the 250 ms position ticker confined to this leaf: the rest of the
/// NowPlaying surface no longer rebuilds 4×/second, so the open options menu
/// stops flickering (its `Menu` content was being re-pushed on every tick).
struct NowPlayingTimeline: View {
  @Environment(MusicState.self) private var music

  var body: some View {
    VStack {
      Scrubber(
        positionMs: music.positionMs,
        durationMs: music.durationMs,
        onSeek: { ms in Task { _ = await music.control(.seek(positionMs: ms)) } }
      )
      HStack {
        Text(timeLabel(music.positionMs))
        Spacer(minLength: 0)
        Text(timeLabel(max(music.durationMs - music.positionMs, 0), remaining: true))
      }
      .font(.caption2)
      .monospacedDigit()
      .foregroundStyle(.tertiary)
    }
  }

  /// `m:ss`, or `-m:ss` for the remaining-time label.
  private func timeLabel(_ ms: Int, remaining: Bool = false) -> String {
    let total = max(ms, 0) / 1_000
    let body = String(format: "%d:%02d", total / 60, total % 60)
    return remaining ? "-\(body)" : body
  }
}
