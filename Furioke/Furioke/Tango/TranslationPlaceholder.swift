import SwiftUI

/// A redacted stand-in shown while a card's gloss / line translation is being
/// fetched, so the layout holds its place instead of popping when the text lands.
/// A sample string rendered at the destination font and redacted to the system's
/// placeholder treatment, so it scales with Dynamic Type and reads as "loading"
/// rather than real text. Shared by the deck browse list and the study back face.
struct TranslationPlaceholder: View {
  /// The font the real text will use, so the bar matches its eventual height.
  var font: Font = Typography.metadata
  /// A sample whose width approximates the pending text — a short word for a gloss,
  /// a phrase for a lyric-line translation.
  var sample: LocalizedStringKey = "translating"
  /// Matches the trailing-aligned meaning column vs. the leading line translation.
  var alignment: TextAlignment = .leading

  var body: some View {
    Text(sample)
      .font(font)
      .multilineTextAlignment(alignment)
      .redacted(reason: .placeholder)
      .accessibilityLabel("Translating")
  }
}
