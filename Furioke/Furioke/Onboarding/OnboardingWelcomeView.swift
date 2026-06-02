import SwiftUI

/// The welcome hero — the first thing a new user sees. Communicates the core
/// value (sing along, understand the lyrics, save words) and the kanji-difficulty
/// pain point Furioke solves. The actions live in the flow's shared chrome: the
/// prominent "Start tutorial" CTA and a quiet "Already have an account? Log in"
/// link in the bottom bar, with Skip and the language picker in the top bar.
struct OnboardingWelcomeView: View {
  var body: some View {
    VStack(spacing: Spacing.xl) {
      Image("AppLogo")
        .resizable()
        .scaledToFit()
        .frame(width: 80, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityHidden(true)
      VStack(spacing: Spacing.m) {
        Text("Welcome to Furioke")
          .font(Typography.pageTitle)
          .multilineTextAlignment(.center)
        Text(
          "Sing along with Japanese songs, understand the lyrics, and save words you want to learn."
        )
        .font(Typography.body)
        .multilineTextAlignment(.center)
        Text(
          "Japanese lyrics can be hard when you don't know the kanji well. Furioke adds furigana, translations, and word-level tools to help."
        )
        .font(Typography.metadata)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      }
    }
    .padding(.horizontal, Spacing.xl)
  }
}
