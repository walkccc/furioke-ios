import SwiftUI

/// The ordered first-launch onboarding sequence: a welcome hero, two real
/// inline setup steps (provider, native language), then six illustrated
/// teaching cards. `welcome` is the intro; the remaining eight are the tutorial
/// steps the progress dots track.
enum OnboardingStep: Int, CaseIterable, Identifiable {
  case welcome
  case provider
  case nativeLanguage
  case search
  case library
  case play
  case helpers
  case longPress
  case tango

  var id: Int {
    rawValue
  }

  var isWelcome: Bool {
    self == .welcome
  }

  var isLast: Bool {
    self == .tango
  }

  /// Tutorial steps exclude the welcome intro.
  static var tutorialCount: Int {
    allCases.count - 1
  }

  /// Zero-based position among the tutorial steps (welcome is `-1` and shows no
  /// progress dots).
  var tutorialIndex: Int {
    rawValue - 1
  }
}

/// The first-launch onboarding flow. Presented once as a full-screen cover over
/// `AppShell` and gated by `PreferencesState.hasCompletedOnboarding`. Fully
/// guest-first: it never requires a session and never blocks on a provider
/// connection. Both "Get started" and every "Skip" route through
/// `PreferencesState.completeOnboarding()`, which flips the gating flag and so
/// dismisses the cover.
struct OnboardingFlow: View {
  @Environment(AuthService.self) private var auth
  @Environment(PreferencesState.self) private var preferences

  @State private var step: OnboardingStep = .welcome
  /// The sign-in prompt is hosted here (not via the shared app flag) because the
  /// flow is the topmost cover — a sheet bound to the shell's flag underneath
  /// could not present. It dismisses on "Not Now" (the sheet's own dismiss) or
  /// once the guest upgrades to a permanent account.
  @State private var showSignIn = false

  var body: some View {
    ZStack {
      OnboardingBackdrop()
      VStack(spacing: 0) {
        if step.isWelcome {
          welcomeTopBar
            .transition(.opacity)
        } else {
          topBar
            .transition(.opacity)
        }
        Spacer(minLength: 0)
        content
          .id(step)
          .transition(.opacity)
        Spacer(minLength: 0)
        bottomBar
      }
      .padding(.top, Spacing.l)
      .padding(.bottom, Spacing.xl)
    }
    // Force the brand accent. The cover is presented above the TabView that
    // applies it app-wide, so without this its tint-driven controls (the
    // prominent CTA, the language menu) fall back to the system accent.
    .tint(Color("AccentColor"))
    .sheet(isPresented: $showSignIn) {
      SignInView()
    }
    // A successful guest → permanent upgrade closes the sign-in sheet; the flow
    // itself continues from the same step.
    .onChange(of: auth.isSignedIn) { _, signedIn in
      if signedIn { showSignIn = false }
    }
  }

  // MARK: - Welcome top bar

  /// The welcome screen's chrome: a compact app-language picker in the
  /// top-leading corner (so the user can switch the interface — and thus the
  /// whole tutorial — into their own language before starting) and the Skip
  /// escape hatch in the top-trailing corner, the same corner Skip occupies on
  /// every tutorial step.
  private var welcomeTopBar: some View {
    HStack {
      languageMenu
      Spacer()
      Button(action: complete) {
        Text("Skip")
          .font(Typography.metadata)
          .padding(.horizontal, Spacing.s)
          .frame(height: 44)
      }
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)
      .accessibilityLabel("Skip onboarding")
    }
    .padding(.horizontal, Spacing.l)
  }

  /// A compact globe-icon menu over `LanguagePreference`. Icon-only so it sits
  /// quietly in the corner opposite Skip; the current language reads out via the
  /// accessibility label rather than a visible chip. Changing it updates the
  /// root `\.locale` (driven by `PreferencesState`), which re-renders the
  /// presented cover, so the tutorial copy switches language live.
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

  // MARK: - Top bar

  /// Back (leading) + centered progress dots + Skip (trailing), shown on the
  /// tutorial steps. Skip is always available and completes onboarding.
  private var topBar: some View {
    ZStack {
      progressDots
      HStack {
        Button(action: goBack) {
          Image(systemName: "chevron.left")
            .font(.system(size: 17, weight: .semibold))
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Back")

        Spacer()

        Button(action: complete) {
          Text("Skip")
            .font(Typography.metadata)
            .padding(.horizontal, Spacing.s)
            .frame(height: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Skip onboarding")
      }
    }
    .padding(.horizontal, Spacing.l)
  }

  private var progressDots: some View {
    HStack(spacing: Spacing.xs) {
      ForEach(0 ..< OnboardingStep.tutorialCount, id: \.self) { index in
        Circle()
          .fill(index == step.tutorialIndex ? Color("AccentColor") : Color.secondary.opacity(0.28))
          .frame(width: 7, height: 7)
      }
    }
    .accessibilityElement()
    .accessibilityLabel("Step \(step.tutorialIndex + 1) of \(OnboardingStep.tutorialCount)")
  }

  // MARK: - Content

  @ViewBuilder
  private var content: some View {
    switch step {
    case .welcome:
      OnboardingWelcomeView()
    case .provider:
      OnboardingProviderStep()
    case .nativeLanguage:
      OnboardingNativeLanguageStep()
    case .search:
      OnboardingTeachingCard(
        title: "Search for a song",
        message: "Find any Japanese song you love, right from the Search tab."
      ) { OnboardingGlyphSketch(systemName: "magnifyingglass") }
    case .library:
      OnboardingTeachingCard(
        title: "Add it to your library",
        message: "Save a song to your library so it's always one tap away."
      ) { OnboardingGlyphSketch(systemName: "music.note.list") }
    case .play:
      OnboardingTeachingCard(
        title: "Play along with lyrics",
        message: "Tap a song to play along and follow lyrics that move with the music."
      ) { OnboardingGlyphSketch(systemName: "play.circle") }
    case .helpers:
      OnboardingTeachingCard(
        title: "Toggle the lyric helpers",
        message: "Use the toolbar in the top-right to turn furigana on or off, and add rōmaji and translations whenever you want them."
      ) { OnboardingHelpersSketch() }
    case .longPress:
      OnboardingTeachingCard(
        title: "Save or fix any word",
        message: "Long-press a word to save it to your Tango List — or override its reading or meaning."
      ) { OnboardingLongPressSketch() }
    case .tango:
      OnboardingTeachingCard(
        title: "Your Tango List",
        message: "Saved words live here with their translation and the lyric line they came from — and you can play that exact line. Review them as a list or study with flashcards."
      ) { OnboardingTangoSketch() }
    }
  }

  // MARK: - Bottom bar

  /// The adaptive call-to-action. Welcome offers a single prominent Start plus
  /// one quiet returning-user log-in link (Skip lives in the top bar); the last
  /// step finishes with "Got it"; every step in between advances with "Continue".
  private var bottomBar: some View {
    VStack(spacing: Spacing.s) {
      Button(action: primaryAction) {
        Text(primaryLabel)
          .font(.system(size: 17, weight: .semibold))
          .frame(maxWidth: .infinity)
          .padding(.vertical, Spacing.s)
      }
      .buttonStyle(.glassProminent)
      .controlSize(.large)
      .accessibilityLabel(primaryLabel)

      if step.isWelcome {
        Button { showSignIn = true } label: {
          Text("Already have an account? Log in")
            .font(Typography.metadata)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.xs)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color("AccentColor"))
        .accessibilityLabel("Already have an account? Log in")
      }
    }
    .padding(.horizontal, Spacing.xl)
  }

  private var primaryLabel: LocalizedStringKey {
    if step.isWelcome { return "Start tutorial" }
    // "Get started" (not "Got it") for the finish action: it reads as entering
    // the app, and avoids colliding with the flashcard "Got it" string, which
    // localizes to "I memorized it".
    if step.isLast { return "Get started" }
    return "Continue"
  }

  private func primaryAction() {
    if step.isLast {
      complete()
    } else {
      advance()
    }
  }

  // MARK: - Navigation

  private func advance() {
    guard let next = OnboardingStep(rawValue: step.rawValue + 1) else { return }
    withAnimation(Motion.ease) { step = next }
  }

  private func goBack() {
    guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
    withAnimation(Motion.ease) { step = previous }
  }

  /// Mark onboarding done. Flipping the persisted flag dismisses the cover (its
  /// presentation is bound to `!hasCompletedOnboarding`).
  private func complete() {
    preferences.completeOnboarding()
  }
}

/// A soft, brand-aligned backdrop — sage + warm radial washes over the grouped
/// background tone — shared by every onboarding page. Pure colour, so it stays
/// legible in light and dark and under Reduce Transparency.
struct OnboardingBackdrop: View {
  var body: some View {
    ZStack {
      Color(.systemGroupedBackground)
      RadialGradient(
        colors: [Color("AccentColor").opacity(0.28), .clear],
        center: .topLeading,
        startRadius: 0,
        endRadius: 480
      )
      RadialGradient(
        colors: [Color.orange.opacity(0.10), .clear],
        center: UnitPoint(x: 0.90, y: 0.12),
        startRadius: 0,
        endRadius: 360
      )
      RadialGradient(
        colors: [Color("AccentColor").opacity(0.14), .clear],
        center: .bottomTrailing,
        startRadius: 0,
        endRadius: 440
      )
    }
    .ignoresSafeArea()
  }
}
