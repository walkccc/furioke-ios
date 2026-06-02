import SwiftUI

/// The centered sign-in / empty-state prompt shared by the Library and 単語 tabs:
/// an `EmptyState` with a glass-prominent **Sign In** button as its action. The
/// button keeps its layout space even when hidden (`showsSignIn == false`), which
/// matches the reserved action row every other empty state renders — so the icon
/// sits at the same vertical height whether or not there's something to sign into.
/// The fixed message reservation and the mini-player bottom inset both live in
/// `EmptyState` now, so every empty state lands in the same place.
struct SignInPrompt: View {
  let systemImage: String
  let title: LocalizedStringKey
  let message: LocalizedStringKey
  let showsSignIn: Bool
  let onSignIn: () -> Void

  var body: some View {
    EmptyState(systemImage: systemImage, title: title, message: message) {
      Button(action: onSignIn) {
        Text("Sign In")
          .padding(.horizontal, Spacing.xl)
          .padding(.vertical, Spacing.s)
      }
      .buttonStyle(.glassProminent)
      // Hidden (but still occupying space) when there's nothing to sign into.
      .opacity(showsSignIn ? 1 : 0)
      .disabled(!showsSignIn)
      .accessibilityHidden(!showsSignIn)
    }
  }
}
