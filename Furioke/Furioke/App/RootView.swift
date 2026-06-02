import SwiftUI

/// Guest-first root. The app is usable without signing in: on cold start with no
/// Keychain session, `AuthService` bootstraps an anonymous guest session and this
/// view renders the `AppShell` for guest and permanent sessions alike. The
/// loading surface shows only while the initial restore + anonymous bootstrap are
/// in flight, with a retry affordance if the bootstrap fails. The shared in-app
/// sign-in prompt is hosted here as a sheet so any reserved-feature gate or the
/// Settings "Sign in" affordance can present it.
struct RootView: View {
  @Environment(AuthService.self) private var auth

  var body: some View {
    @Bindable var auth = auth

    Group {
      switch auth.state {
      case .loading:
        if auth.bootstrapFailed {
          GuestBootstrapErrorView { auth.retryBootstrap() }
        } else {
          ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      case .guest, .signedIn:
        AppShell()
      }
    }
    .sheet(isPresented: $auth.isSignInPromptPresented) {
      SignInView()
    }
  }
}

/// Shown when the anonymous bootstrap can't complete (provider disabled, CAPTCHA /
/// rate limit, or offline). Offers a retry rather than wedging on a spinner.
private struct GuestBootstrapErrorView: View {
  let onRetry: () -> Void

  var body: some View {
    VStack(spacing: Spacing.l) {
      Image(systemName: "wifi.exclamationmark")
        .font(.system(size: 44, weight: .semibold))
        .foregroundStyle(.secondary)
      Text("Couldn't start furioke")
        .font(Typography.pageTitle)
      Text("Check your connection and try again.")
        .font(Typography.body)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      Button(action: onRetry) {
        Text("Try Again")
          .padding(.horizontal, Spacing.xl)
          .padding(.vertical, Spacing.s)
      }
      .buttonStyle(.glassProminent)
    }
    .padding(.horizontal, Spacing.xl)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
