import Observation

// Serializes the mini-player ↔ NowPlayingSheet morph so rapid expand/collapse
// cycles can't interleave animations. Inputs in transitional phases are
// silently dropped — the design treats the transition itself as authoritative.

@Observable
@MainActor
final class MiniPlayerExpansion {
  enum Phase: Equatable {
    case collapsed
    case expanding
    case expanded
    case collapsing
  }

  private(set) var phase: Phase = .collapsed

  var isExpanded: Bool {
    phase == .expanded
  }

  var isSheetPresented: Bool {
    phase == .expanding || phase == .expanded
  }

  func requestExpand() {
    guard phase == .collapsed else { return }
    phase = .expanding
  }

  func requestCollapse() {
    guard phase == .expanded else { return }
    phase = .collapsing
  }

  func didFinishExpanding() {
    guard phase == .expanding else { return }
    phase = .expanded
  }

  func didFinishCollapsing() {
    guard phase == .collapsing else { return }
    phase = .collapsed
  }
}
