import SwiftUI

/// The leading rounded hero title pinned at the top of a tab (Library, Search,
/// Settings), with an optional metadata subtitle beneath. One source for the
/// shared top offset and padding so every tab's title lands at the same place,
/// replacing the stock navigation large title.
struct PageTitle: View {
  let title: LocalizedStringKey
  var subtitle: LocalizedStringKey?

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Text(title)
        .font(Typography.pageTitle)
      if let subtitle {
        Text(subtitle)
          .font(Typography.metadata)
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, Spacing.l)
    .padding(.top, Spacing.l)
    .padding(.bottom, Spacing.s)
  }
}
