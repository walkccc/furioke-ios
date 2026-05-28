import SwiftUI

// Transport control with `.bounce` symbol effect on tap and a `.scale`
// press-down response. `accessibilityLabel` is set by construction — the
// caller picks a `Kind` rather than passing a glyph name + label pair.

struct TransportButton: View {
  enum Kind {
    case play, pause, previous, next

    var systemImage: String {
      switch self {
      case .play: "play.fill"
      case .pause: "pause.fill"
      case .previous: "backward.fill"
      case .next: "forward.fill"
      }
    }

    var label: String {
      switch self {
      case .play: "Play"
      case .pause: "Pause"
      case .previous: "Previous track"
      case .next: "Next track"
      }
    }
  }

  private let kind: Kind
  private let isEnabled: Bool
  private let action: () -> Void

  @State private var bounceTrigger: Int = 0

  init(_ kind: Kind, isEnabled: Bool = true, action: @escaping () -> Void) {
    self.kind = kind
    self.isEnabled = isEnabled
    self.action = action
  }

  var body: some View {
    Button {
      bounceTrigger &+= 1
      action()
    } label: {
      Image(systemName: kind.systemImage)
        .symbolEffect(.bounce, value: bounceTrigger)
        .contentShape(Rectangle())
    }
    .buttonStyle(TransportButtonStyle())
    .disabled(!isEnabled)
    .opacity(isEnabled ? 1 : 0.35)
    .accessibilityLabel(kind.label)
  }
}

private struct TransportButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
      .animation(Motion.pop, value: configuration.isPressed)
  }
}
