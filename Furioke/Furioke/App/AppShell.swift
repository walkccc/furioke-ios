import SwiftUI

// Composition root for the tab bar + mini-player + NowPlayingSheet layout.
// Owns the `@Namespace` shared between `MiniPlayer` and `NowPlayingSheet` for
// the matchedGeometry artwork / title / artist morph.
//
// Section 6 fills in the feature views, the `tabViewBottomAccessory` hosting
// of `MiniPlayer`, and the sheet-presentation wiring driven by
// `MiniPlayerExpansion`. This file is intentionally minimal — feature code is
// not yet permitted to reach in.

struct AppShell: View {
  @State private var selection: AppTab = .library
  @State private var expansion: MiniPlayerExpansion = .init()
  @Namespace private var playerNamespace

  var body: some View {
    LiquidGlassTabBar(
      selection: $selection,
      library: { Color.clear },
      search: { Color.clear },
      settings: { Color.clear }
    )
    .environment(expansion)
  }
}
