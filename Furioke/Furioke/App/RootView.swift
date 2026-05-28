import SwiftUI

/// The sign-in gate: switches between the sign-in surface and the `AppShell`
/// based on the Supabase session, with no app restart when the session changes
/// at runtime.
struct RootView: View {
  @Environment(AuthService.self) private var auth

  var body: some View {
    switch auth.state {
    case .loading:
      ProgressView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    case .signedOut:
      SignInView()
    case .signedIn:
      AppShell()
    }
  }
}
