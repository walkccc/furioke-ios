import SwiftUI

/// The app's one transient-toast style: a glass pill carrying either a spinner
/// (an in-progress activity) or a leading SF Symbol (a discrete notice/result),
/// followed by a short label. Every transient banner on the Now Playing surface
/// — furigana/translation progress, the translation and playback notices, the
/// saved confirmation — is built from this so they read as a single vocabulary.
///
/// Built on `GlassCapsule` for the shared glass + metric treatment. The toast is
/// transition-agnostic: each call site applies its own move-edge transition
/// (top-docked notices slide from the top, the saved toast from the bottom).
struct Toast: View {
  enum Kind: Equatable {
    /// An ongoing activity — renders a small spinner.
    case progress
    /// A discrete notice or result — renders the named SF Symbol.
    case icon(String)
  }

  let text: String
  let kind: Kind

  var body: some View {
    GlassCapsule {
      HStack(spacing: Spacing.s) {
        switch kind {
        case .progress:
          ProgressView().controlSize(.small)
        case let .icon(systemName):
          Image(systemName: systemName)
        }
        Text(text)
      }
    }
    .foregroundStyle(.secondary)
  }
}
