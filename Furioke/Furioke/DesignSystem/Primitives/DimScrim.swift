import SwiftUI

/// The app's one focus-overlay backdrop: a faint full-screen scrim that pushes the
/// surface behind a floating card (the reading editor) back and takes a tap to
/// dismiss. Shared by the NowPlaying playback overlay and the reading-overrides
/// editor so both recede the same way. Fades in/out via `.opacity`; the floating
/// card supplies its own transition on top.
struct DimScrim: View {
  let onTap: () -> Void

  var body: some View {
    Rectangle()
      .fill(.black.opacity(0.18))
      .ignoresSafeArea()
      .contentShape(Rectangle())
      .onTapGesture { onTap() }
      .transition(.opacity)
  }
}
