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
}

extension OpaqueMaterial {
  var color: Color {
    switch self {
    case .contentSurface: Color(.systemBackground)
    case .popoverSurface: Color(.secondarySystemBackground)
    }
  }
}
