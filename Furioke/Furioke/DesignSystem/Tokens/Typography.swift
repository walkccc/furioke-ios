import SwiftUI

// All tokens build on relative SwiftUI text styles so every surface scales
// with Dynamic Type.

enum Typography {
  static let pageTitle: Font = .system(.largeTitle, design: .rounded, weight: .bold)
  static let sectionTitle: Font = .system(.title3, design: .rounded, weight: .semibold)
  static let body: Font = .system(.body)
  static let metadata: Font = .system(.subheadline, weight: .medium)
  static let lyricActive: Font = .system(.title2, design: .rounded, weight: .semibold)
  static let lyricRest: Font = .system(.title3, design: .rounded, weight: .regular)
  static let furigana: Font = .system(.caption2, design: .rounded, weight: .regular)
}
