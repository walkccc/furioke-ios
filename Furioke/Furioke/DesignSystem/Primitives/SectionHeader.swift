import SwiftUI

// Title row with an optional trailing action slot.

struct SectionHeader<Trailing: View>: View {
  private let title: LocalizedStringKey
  private let trailing: Trailing

  init(_ title: LocalizedStringKey, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
    self.title = title
    self.trailing = trailing()
  }

  var body: some View {
    HStack(spacing: Spacing.s) {
      Text(title).font(Typography.sectionTitle)
      Spacer(minLength: 0)
      trailing
    }
    .padding(.horizontal, Spacing.l)
    .padding(.vertical, Spacing.s)
  }
}
