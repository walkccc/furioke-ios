import SwiftUI

/// The in-app sign-in prompt, presented as a sheet from the reserved-feature gate
/// (`requirePermanentAccount()`) and from Settings. Offers Sign in with Apple
/// (native, driven by `AppleSignInController`) and Google. Genuine failures
/// surface inline; user-cancellation stays silent (handled in `AuthService`). On
/// a successful upgrade `AuthService` clears the prompt flag, dismissing the sheet.
struct SignInView: View {
  @Environment(AuthService.self) private var auth
  @Environment(PreferencesState.self) private var preferences
  @Environment(\.dismiss) private var dismiss
  @State private var isSigningIn = false

  var body: some View {
    VStack(spacing: Spacing.xl) {
      HStack {
        Spacer()
        languageMenu
      }
      .padding(.horizontal, Spacing.l)
      .padding(.top, Spacing.s)
      Spacer()
      VStack(spacing: Spacing.s) {
        Image("AppLogo")
          .resizable()
          .scaledToFit()
          .frame(width: 72, height: 72)
          .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
          .accessibilityHidden(true)
        Text("furioke")
          .font(Typography.pageTitle)
        Text("Sign in to translate, save songs, and build your flashcard deck.")
          .font(Typography.body)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          // Reserve a constant height so the title block stays put regardless of
          // how many lines the localized subtitle wraps to.
          .lineLimit(3, reservesSpace: true)
      }
      Spacer()
      if let error = auth.lastSignInError {
        Text(error)
          .font(Typography.metadata)
          .foregroundStyle(.red)
          .multilineTextAlignment(.center)
          .padding(.horizontal, Spacing.xl)
      }
      VStack(spacing: Spacing.m) {
        appleButton
        googleButton
        Button(action: { dismiss() }) {
          Text("Not Now")
            .font(Typography.metadata)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.xs)
        }
        .buttonStyle(.plain)
        .disabled(isSigningIn)
      }
      .padding(.horizontal, Spacing.xl)
      .padding(.bottom, Spacing.xxl)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  /// A compact globe-icon menu over `LanguagePreference`, mirroring the
  /// onboarding welcome screen's icon-only picker. Changing it updates the root
  /// `\.locale` (driven by `PreferencesState`), re-rendering the sheet so its
  /// copy switches live.
  private var languageMenu: some View {
    Menu {
      Picker("Language", selection: languageBinding) {
        ForEach(LanguagePreference.allCases) { language in
          Text(language.label).tag(language)
        }
      }
    } label: {
      Image(systemName: "translate")
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(Color("AccentColor"))
        .frame(width: 44, height: 44)
    }
    .accessibilityLabel("Language")
    .accessibilityValue(preferences.language.label)
  }

  private var languageBinding: Binding<LanguagePreference> {
    Binding(get: { preferences.language }, set: { preferences.language = $0 })
  }

  /// Sign in with Apple — driving the `ASAuthorizationController` flow in
  /// `AuthService`. Shares the liquid-glass capsule treatment and height with
  /// `googleButton` via `providerButton`.
  private var appleButton: some View {
    providerButton(title: "Sign in with Apple") {
      signIn { await auth.signInWithApple() }
    } icon: {
      Image(systemName: "applelogo")
        .font(.system(size: 16, weight: .medium))
    }
  }

  private var googleButton: some View {
    providerButton(title: "Sign in with Google") {
      signIn { await auth.signInWithGoogle() }
    } icon: {
      Image("GoogleIcon")
        .renderingMode(.original)
        .resizable()
        .scaledToFit()
        .frame(width: 16, height: 16)
    }
  }

  /// A liquid-glass capsule sign-in button. Both providers route through here so
  /// they share an identical height, glyph slot, and glass material — only the
  /// icon and label differ.
  private func providerButton(
    title: LocalizedStringKey,
    action: @escaping () -> Void,
    @ViewBuilder icon: () -> some View
  ) -> some View {
    Button(action: action) {
      HStack(spacing: Spacing.s) {
        icon()
          .frame(width: 22, height: 22)
        Text(title)
          .font(.system(size: 17, weight: .medium))
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, Spacing.s)
    }
    .buttonStyle(.glass)
    .controlSize(.large)
    .disabled(isSigningIn)
    .accessibilityLabel(title)
  }

  private func signIn(_ action: @escaping () async -> Void) {
    isSigningIn = true
    Task {
      await action()
      isSigningIn = false
    }
  }
}
