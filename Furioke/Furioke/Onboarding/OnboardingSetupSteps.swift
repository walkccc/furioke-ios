import SwiftUI

/// Shared layout for an onboarding setup step: a centered title + explanatory
/// copy above an interactive control. Mirrors the teaching card's proportions so
/// the flow reads as one consistent sequence even though these steps capture
/// real preferences.
private struct OnboardingStepLayout<Control: View>: View {
  let systemImage: String
  let title: LocalizedStringKey
  let message: LocalizedStringKey
  @ViewBuilder var control: () -> Control

  var body: some View {
    VStack(spacing: Spacing.xl) {
      VStack(spacing: Spacing.m) {
        Image(systemName: systemImage)
          .font(.system(size: 44, weight: .regular))
          .foregroundStyle(Color("AccentColor"))
          .symbolRenderingMode(.hierarchical)
          .accessibilityHidden(true)
        Text(title)
          .font(Typography.sectionTitle)
          .multilineTextAlignment(.center)
        Text(message)
          .font(Typography.body)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
      control()
    }
    .padding(.horizontal, Spacing.xl)
  }
}

/// Step 1 — choose a music provider. Renders the same `ProviderSelector` used in
/// Settings; connecting is best-effort and never blocks advancing, so the step
/// is fully skippable (including when Spotify bounces out to its app).
struct OnboardingProviderStep: View {
  var body: some View {
    OnboardingStepLayout(
      systemImage: "music.note.list",
      title: "Choose your music provider",
      message: "Pick the service you already listen to, so Furioke can play along with your songs."
    ) {
      ProviderSelector()
    }
  }
}

/// Step 2 — choose the native (explanation) language. Updates
/// `PreferencesState.nativeLanguage`; offers exactly the real translation
/// targets (English and 中文). Skippable — advancing keeps the current value.
struct OnboardingNativeLanguageStep: View {
  @Environment(PreferencesState.self) private var preferences

  var body: some View {
    OnboardingStepLayout(
      systemImage: "text.bubble",
      title: "Your native language",
      message: "This is the language used for lyric translations and word meanings."
    ) {
      HStack(spacing: Spacing.s) {
        ForEach(NativeLanguagePreference.allCases) { language in
          languageCard(language)
        }
      }
    }
  }

  private func languageCard(_ language: NativeLanguagePreference) -> some View {
    let isSelected = preferences.nativeLanguage == language
    let shape = RoundedRectangle(cornerRadius: Radii.md, style: .continuous)
    return Button {
      withAnimation(Motion.pop) { preferences.nativeLanguage = language }
    } label: {
      Text(language.label)
        .font(Typography.body.weight(.medium))
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.l)
        .foregroundStyle(isSelected ? Color("AccentColor") : .primary)
        .background(
          shape.fill(isSelected ? Color("AccentColor").opacity(0.18) : Color(.quaternarySystemFill))
        )
        .overlay(shape.strokeBorder(isSelected ? Color("AccentColor") : .clear, lineWidth: 2))
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    .accessibilityLabel(Text(language.label))
  }
}
