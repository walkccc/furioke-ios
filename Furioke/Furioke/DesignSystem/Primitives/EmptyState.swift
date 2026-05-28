import SwiftUI

// Icon + title + body + optional action surface.

struct EmptyState<Action: View>: View {
  private let systemImage: String
  private let title: String
  private let message: String
  private let action: Action

  init(
    systemImage: String,
    title: String,
    message: String,
    @ViewBuilder action: () -> Action = { EmptyView() }
  ) {
    self.systemImage = systemImage
    self.title = title
    self.message = message
    self.action = action()
  }

  var body: some View {
    VStack(spacing: Spacing.m) {
      Image(systemName: systemImage)
        .font(.system(size: 44, weight: .regular))
        .foregroundStyle(.secondary)
      Text(title).font(Typography.sectionTitle)
      Text(message)
        .font(Typography.body)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      action
        .padding(.top, Spacing.s)
    }
    .padding(Spacing.xl)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
