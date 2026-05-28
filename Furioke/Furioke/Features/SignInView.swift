import SwiftUI

/// Full-screen sign-in surface shown when no Supabase session is present. The
/// sign-in button is the one glass chrome affordance here;
/// genuine failures surface inline, user-cancellation stays silent (handled in
/// `AuthService`).
struct SignInView: View {
  @Environment(AuthService.self) private var auth
  @State private var isSigningIn = false

  var body: some View {
    VStack(spacing: Spacing.xl) {
      Spacer()
      VStack(spacing: Spacing.s) {
        Image(systemName: "music.note")
          .font(.system(size: 56, weight: .semibold))
          .foregroundStyle(.tint)
        Text("furioke")
          .font(Typography.pageTitle)
        Text("Listen and read along with furigana.")
          .font(Typography.body)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
      Spacer()
      if let error = auth.lastSignInError {
        Text(error)
          .font(Typography.metadata)
          .foregroundStyle(.red)
          .multilineTextAlignment(.center)
          .padding(.horizontal, Spacing.xl)
      }
      Button(action: signIn) {
        Label("Sign in with Google", systemImage: "person.crop.circle")
          .frame(maxWidth: .infinity)
          .padding(.vertical, Spacing.s)
      }
      .buttonStyle(.glassProminent)
      .disabled(isSigningIn)
      .padding(.horizontal, Spacing.xl)
      .padding(.bottom, Spacing.xxl)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func signIn() {
    isSigningIn = true
    Task {
      await auth.signInWithGoogle()
      isSigningIn = false
    }
  }
}
