import SwiftUI

// Three role-based animation presets. Feature code picks a role; it never
// declares bespoke spring or ease durations.

enum Motion {
  static let pop: Animation = .spring(response: 0.28, dampingFraction: 0.7)
  static let ease: Animation = .easeInOut(duration: 0.22)
  /// Drives the NowPlaying zoom present/dismiss. Duration-based (not a spring) so
  /// the transition has a definite, short completion — the cover's interactive
  /// swipe-to-dismiss only arms once the open finishes, so a fast, deterministic
  /// open keeps that wait imperceptible.
  static let sheet: Animation = .snappy(duration: 0.3, extraBounce: 0)
}
