import Observation
import SwiftUI

/// The app's single out-of-quota notice. Translation spends a per-user daily quota
/// (the backend returns 429 at the limit), and several features touch it — the
/// flashcard deck's lazy gloss fetch, the study deck's prefetch. Rather than each
/// re-implementing the banner, they all route a 429 through this one shared
/// instance, and a single host (`AppShell`, via `quotaNoticeToast()`) renders the
/// `Toast` over the tab content. That's what makes the same notice reusable from
/// anywhere without duplicating the presentation.
@Observable
@MainActor
final class QuotaNotice {
  /// Whether the translation out-of-quota toast is currently shown. Host views
  /// observe this to render the toast; it auto-clears a few seconds after each
  /// trigger so it never lingers.
  private(set) var translationLimitShown = false

  @ObservationIgnored private var resetTask: Task<Void, Never>?

  /// Raise the translation out-of-quota toast. Idempotent while already shown —
  /// each call just restarts the auto-dismiss timer — so a burst of 429s (the deck
  /// retrying several cards) reads as one steady notice rather than a flicker.
  func translationLimitReached() {
    withAnimation(Motion.ease) { translationLimitShown = true }
    resetTask?.cancel()
    resetTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(4))
      guard let self, !Task.isCancelled else { return }
      withAnimation(Motion.ease) { self.translationLimitShown = false }
    }
  }
}

private struct QuotaNoticeToast: ViewModifier {
  @Environment(QuotaNotice.self) private var quota

  func body(content: Content) -> some View {
    content.overlay(alignment: .top) {
      if quota.translationLimitShown {
        // Built from the same `Toast` vocabulary as the Now Playing notices; the
        // copy leads with the limit and points at the upgrade so the learner knows
        // translations are spent for the day *and* how to lift the cap.
        Toast(
          text: "Daily translation limit reached. Upgrade for unlimited translations.",
          kind: .icon("sparkles")
        )
        .padding(.top, Spacing.xxl)
        .padding(.horizontal, Spacing.l)
        .transition(.move(edge: .top).combined(with: .opacity))
      }
    }
  }
}

extension View {
  /// Overlay the app's shared translation out-of-quota toast, driven by the
  /// `QuotaNotice` in the environment. Applied once at the app shell so every
  /// feature that raises the notice surfaces the same banner over the tab content.
  func quotaNoticeToast() -> some View {
    modifier(QuotaNoticeToast())
  }
}
