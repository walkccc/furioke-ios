import SwiftUI

// Three role-based animation presets. Feature code picks a role; it never
// declares bespoke spring or ease durations.

enum Motion {
  static let pop: Animation = .spring(response: 0.28, dampingFraction: 0.7)
  static let ease: Animation = .easeInOut(duration: 0.22)
  static let sheet: Animation = .spring(response: 0.42, dampingFraction: 0.82)
}
