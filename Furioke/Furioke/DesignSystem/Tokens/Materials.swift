import SwiftUI

// Two disjoint token types so the chrome-vs-content split is enforced at the
// type level: `Surface` only accepts `OpaqueMaterial`, `GlassChrome` only
// accepts `GlassRole`, and passing one where the other is expected fails to
// compile.

enum GlassRole {
  case chromeGlass
  case capsuleTier
  case controlTier
}

enum OpaqueMaterial {
  case contentSurface
  case popoverSurface
}

enum Materials {
  static let chromeGlass: GlassRole = .chromeGlass
  static let capsuleTier: GlassRole = .capsuleTier
  static let controlTier: GlassRole = .controlTier

  static let contentSurface: OpaqueMaterial = .contentSurface
  static let popoverSurface: OpaqueMaterial = .popoverSurface
}

extension GlassRole {
  var glass: Glass {
    switch self {
    case .chromeGlass: .regular
    case .capsuleTier: .regular
    case .controlTier: .regular.interactive()
    }
  }

  /// The role's glass, brightened with a white tint when `isActive` so an "on"
  /// control reads as a lit-up disc/pill rather than a colour change on its glyph
  /// alone. The single source of the lit-glass idiom shared by the NowPlaying
  /// display discs and the reading editor's toggles.
  func glass(active isActive: Bool) -> Glass {
    isActive ? glass.tint(.white.opacity(0.45)) : glass
  }
}

extension OpaqueMaterial {
  var color: Color {
    switch self {
    case .contentSurface: Color(.systemBackground)
    case .popoverSurface: Color(.secondarySystemBackground)
    }
  }
}
