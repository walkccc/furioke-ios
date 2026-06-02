import SwiftUI

/// A left-to-right wrapping layout for ruby token cells. SwiftUI has no native
/// ruby text, so a lyric line is laid out as a flow of `[reading-over-surface]`
/// cells that wrap at the container width. Used by `RubyLine`.
struct RubyFlowLayout: Layout {
  var horizontalSpacing: CGFloat = 0
  var verticalSpacing: CGFloat = 2

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
    // A vertical ScrollView measures its content with an unspecified (nil) or
    // infinite width proposal. Only `nil` was guarded before, so an infinite
    // proposal slipped through as the wrap limit — no token ever exceeded it,
    // the whole line laid out on one row, and the layout reported itself as
    // infinitely wide, which then overflowed and clipped instead of wrapping.
    let proposedWidth = proposal.width.flatMap { $0.isFinite ? $0 : nil }
    let maxWidth = proposedWidth ?? .greatestFiniteMagnitude
    var x: CGFloat = 0
    var rowHeight: CGFloat = 0
    var totalHeight: CGFloat = 0
    var widestRow: CGFloat = 0

    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if x > 0, x + size.width > maxWidth {
        totalHeight += rowHeight + verticalSpacing
        widestRow = max(widestRow, x - horizontalSpacing)
        x = 0
        rowHeight = 0
      }
      x += size.width + horizontalSpacing
      rowHeight = max(rowHeight, size.height)
    }
    totalHeight += rowHeight
    widestRow = max(widestRow, x - horizontalSpacing)

    // Report the consumed width, never the proposal — echoing back an infinite
    // proposal is what broke wrapping. With a finite proposal we fill it (so
    // leading alignment behaves); otherwise we report the true content extent.
    let width = proposedWidth ?? max(widestRow, 0)
    return CGSize(width: width, height: totalHeight)
  }

  func placeSubviews(
    in bounds: CGRect,
    proposal _: ProposedViewSize,
    subviews: Subviews,
    cache _: inout ()
  ) {
    var x = bounds.minX
    var y = bounds.minY
    var rowHeight: CGFloat = 0

    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if x > bounds.minX, (x - bounds.minX) + size.width > bounds.width {
        x = bounds.minX
        y += rowHeight + verticalSpacing
        rowHeight = 0
      }
      subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
      x += size.width + horizontalSpacing
      rowHeight = max(rowHeight, size.height)
    }
  }
}
