import SwiftUI
import UIKit

// Drag-to-seek position bar. Drag previews don't fight live playback updates:
// the caller is expected to suppress incoming `positionMs` during drag and for
// the settling window afterwards (the rule lives with NowPlayingState, not
// here). `.light` haptic fires at the 25 / 50 / 75% detents.

struct Scrubber: View {
  private let positionMs: Int
  private let durationMs: Int
  private let onSeek: (Int) -> Void

  @State private var draftFraction: Double? = nil
  @State private var lastDetent: Int? = nil

  init(positionMs: Int, durationMs: Int, onSeek: @escaping (Int) -> Void) {
    self.positionMs = positionMs
    self.durationMs = durationMs
    self.onSeek = onSeek
  }

  private var fraction: Double {
    if let draftFraction { return draftFraction }
    guard durationMs > 0 else { return 0 }
    return min(max(Double(positionMs) / Double(durationMs), 0), 1)
  }

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule().fill(.quaternary)
        Capsule().fill(.primary).frame(width: proxy.size.width * fraction)
      }
      .frame(height: 6)
      .frame(maxHeight: .infinity)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            let f: Double = clampedFraction(value.location.x, width: proxy.size.width)
            draftFraction = f
            fireHapticIfCrossingDetent(fraction: f)
          }
          .onEnded { value in
            let f: Double = clampedFraction(value.location.x, width: proxy.size.width)
            draftFraction = nil
            lastDetent = nil
            onSeek(Int(f * Double(durationMs)))
          }
      )
    }
    .frame(height: 28)
    .accessibilityElement()
    .accessibilityLabel("Playback position")
    .accessibilityValue(Text(positionLabel))
  }

  private func clampedFraction(_ x: CGFloat, width: CGFloat) -> Double {
    guard width > 0 else { return 0 }
    return min(max(Double(x / width), 0), 1)
  }

  private var positionLabel: String {
    "\(formattedTime(ms: positionMs)) of \(formattedTime(ms: durationMs))"
  }

  private func formattedTime(ms: Int) -> String {
    let total: Int = max(ms, 0) / 1000
    return String(format: "%d:%02d", total / 60, total % 60)
  }

  private func fireHapticIfCrossingDetent(fraction: Double) {
    let detents: [Int] = [25, 50, 75]
    let percent: Int = Int(fraction * 100)
    if let hit = detents.first(where: { abs(percent - $0) <= 1 }) {
      if lastDetent != hit {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        lastDetent = hit
      }
    } else {
      lastDetent = nil
    }
  }
}
