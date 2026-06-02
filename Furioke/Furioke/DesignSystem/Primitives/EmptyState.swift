import SwiftUI

// Icon + title + body + optional action surface.
//
// Every empty state in the app routes through this view so the icon, title, and
// message land at the same vertical position regardless of screen. Three things
// keep that alignment:
//  - the message reserves a fixed line count, so short copy doesn't float the icon up,
//  - the action row always reserves a button's worth of height (a hidden placeholder
//    stands in when a screen offers no action), and
//  - the block centers at the page's true vertical middle by ignoring the container
//    safe area on both edges — so the nav bar (the 単語 tab shows one, the Library
//    tab doesn't) and the floating mini-player accessory (present only while a track
//    plays) don't shift it. Every empty state lands at the same height on every tab
//    and holds it across play/stop.

struct EmptyState<Action: View>: View {
  private let systemImage: String
  private let title: LocalizedStringKey
  private let message: LocalizedStringKey
  private let messageLineReservation: Int?
  private let action: Action

  init(
    systemImage: String,
    title: LocalizedStringKey,
    message: LocalizedStringKey,
    messageLineReservation: Int? = 3,
    @ViewBuilder action: () -> Action = { EmptyView() }
  ) {
    self.systemImage = systemImage
    self.title = title
    self.message = message
    self.messageLineReservation = messageLineReservation
    self.action = action()
  }

  var body: some View {
    VStack(spacing: Spacing.l) {
      VStack(spacing: Spacing.m) {
        Image(systemName: systemImage)
          .font(.system(size: 44, weight: .regular))
          .foregroundStyle(.secondary)
        Text(title).font(Typography.sectionTitle)
        messageText
      }
      actionRow
    }
    .padding(Spacing.xl)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    // Center the block at the page's true vertical middle, not the space under the
    // nav bar or above the mini-player. Tabs differ at the top — the Library tab has
    // no nav bar while the 単語 tab keeps a visible one (its deck controls float over
    // this, still tappable) — and the floating mini-player accessory only insets the
    // bottom while a track plays. Ignoring the container safe area on both edges lands
    // the block at the identical height on every tab and holds it across play/stop;
    // the block is short enough that true centering never reaches the mini-player.
    .ignoresSafeArea(.container, edges: .vertical)
  }

  /// The action button — or, when a screen offers no action, a hidden button that
  /// reserves the same height, so the icon/title/message land at the identical
  /// vertical position on every empty state.
  @ViewBuilder
  private var actionRow: some View {
    if Action.self == EmptyView.self {
      placeholderButton.hidden()
    } else {
      action
    }
  }

  /// Sized to match the real Sign In / Open Settings buttons (both glass-prominent
  /// with the same vertical padding) so the reserved row is exactly button-tall.
  private var placeholderButton: some View {
    Button(action: {}) {
      Text("Sign In")
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.s)
    }
    .buttonStyle(.glassProminent)
  }

  /// The body copy. `messageLineReservation` reserves space for that many lines even
  /// when the copy is shorter — so two `EmptyState`s with differently-sized messages
  /// keep the same block height (and thus the icon lands at the same vertical
  /// position) instead of the shorter copy floating the icon down relative to the
  /// longer one.
  @ViewBuilder
  private var messageText: some View {
    let base = Text(message)
      .font(Typography.body)
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.center)
    if let messageLineReservation {
      base.lineLimit(messageLineReservation, reservesSpace: true)
    } else {
      base
    }
  }
}
