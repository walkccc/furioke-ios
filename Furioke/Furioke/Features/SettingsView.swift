import SwiftUI

/// Settings: music-provider selection + connect / disconnect, appearance +
/// language preferences, and sign out. The provider picker switches the active
/// provider (tearing the previous one down); connect / disconnect then act on
/// whichever provider is selected.
///
/// Rendered in the app's design language rather than a stock grouped `Form`: a
/// pinned rounded hero title over a vertical scroll of `Surface`-backed section
/// cards, each headed by a `SectionHeader`. Music and Appearance share one
/// three-column selector shape (icon + label, the active option highlighted),
/// keeping the screen minimal. The cards stay on the opaque content material per
/// the chrome-vs-content split.
struct SettingsView: View {
  @Environment(AuthService.self) private var auth
  @Environment(MusicState.self) private var music
  @Environment(PreferencesState.self) private var preferences

  @State private var isConnecting = false
  @State private var connectError: String?

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 0) {
        // Custom rounded hero title, matching Library's. Pinned above the scroll
        // at the same top offset (safe area + Spacing.l); the background base
        // extends behind it so the strip above the first card reads seamlessly.
        Text("Settings")
          .font(Typography.pageTitle)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, Spacing.l)
          .padding(.top, Spacing.l)
          .padding(.bottom, Spacing.s)

        ScrollView {
          VStack(alignment: .leading, spacing: Spacing.l) {
            musicSection
            appearanceSection
            customizationSection
            accountSection
          }
          .padding(.top, Spacing.xs)
          .padding(.bottom, Spacing.xl)
        }
      }
      // A quiet brand-aligned base: grouped-background tone with a soft sage wash
      // at the top. Pure color, so it stays legible under Reduce Transparency and
      // matches the seamless strip the pinned hero needs.
      .background(backgroundBase)
      // The custom hero title replaces the system large title.
      .toolbar(.hidden, for: .navigationBar)
    }
  }

  // MARK: - Background

  private var backgroundBase: some View {
    Color(.systemGroupedBackground)
      .overlay(alignment: .top) {
        LinearGradient(
          colors: [Color.accentColor.opacity(0.08), .clear],
          startPoint: .top,
          endPoint: .center
        )
      }
      .ignoresSafeArea()
  }

  // MARK: - Section card

  /// One section group: a `SectionHeader` over an opaque `Surface` card. Every
  /// section reuses this shape so nothing reads as leftover `Form` chrome.
  private func sectionCard<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      SectionHeader(title)
      Surface(material: Materials.contentSurface, cornerRadius: Radii.lg) {
        VStack(alignment: .leading, spacing: Spacing.m) {
          content()
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.horizontal, Spacing.l)
    }
  }

  /// Shared three-column option cell used by both selectors: an icon over a
  /// label. The active option is highlighted with an accent fill + ring (the
  /// filled state is the selection indicator — no checkmark, kept minimal).
  private func optionCard<Icon: View>(
    label: String,
    isSelected: Bool,
    action: @escaping () -> Void,
    @ViewBuilder icon: () -> Icon
  ) -> some View {
    let shape = RoundedRectangle(cornerRadius: Radii.md, style: .continuous)
    return Button(action: action) {
      VStack(spacing: Spacing.xs) {
        icon()
          .frame(height: 30)
        Text(label)
          .font(Typography.metadata)
          .lineLimit(1)
          .minimumScaleFactor(0.75)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, Spacing.m)
      .foregroundStyle(isSelected ? Color.accentColor : .primary)
      .background(
        shape.fill(isSelected ? Color.accentColor.opacity(0.16) : Color(.tertiarySystemFill))
      )
      .overlay(
        shape.strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
      )
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    .accessibilityLabel(label)
  }

  // MARK: - Music

  private var musicSection: some View {
    sectionCard("Music") {
      providerSelector

      // The grid is self-contained: highlight means connected, tapping connects.
      // The only thing that ever appears below it is a connect-failure note.
      if let connectError {
        Text(connectError)
          .font(Typography.metadata)
          .foregroundStyle(.secondary)
      }
    }
  }

  /// Three provider columns mirroring the theme selector: each shows the
  /// provider's brand icon + name. A column is highlighted only while that
  /// provider is the connected one — when nothing is connected, nothing is
  /// highlighted. Tapping a column selects that provider and connects it.
  private var providerSelector: some View {
    HStack(spacing: Spacing.s) {
      ForEach(music.availableProviders) { provider in
        let isConnectedProvider = music.activeProvider == provider && music.isConnected
        let isConnectingProvider = isConnecting && music.activeProvider == provider && !music.isConnected
        optionCard(
          label: provider.displayName,
          isSelected: isConnectedProvider,
          action: { selectProvider(provider) }
        ) {
          Image(providerIcon(provider))
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .opacity(isConnectingProvider ? 0.35 : 1)
            .overlay {
              if isConnectingProvider {
                ProgressView()
              }
            }
        }
      }
    }
  }

  private func providerIcon(_ provider: MusicProvider) -> String {
    switch provider {
    case .spotify: "SpotifyIcon"
    case .appleMusic: "AppleMusicIcon"
    case .youtube: "YoutubeMusicIcon"
    }
  }

  // MARK: - Appearance

  private var appearanceSection: some View {
    sectionCard("Appearance") {
      VStack(alignment: .leading, spacing: Spacing.s) {
        Text("Theme")
          .font(Typography.metadata)
          .foregroundStyle(.secondary)
        themeSelector
      }
      Divider()
      languageRow
    }
  }

  /// Three equal-width theme columns; the active theme is accent-tinted with the
  /// filled-card highlight (no checkmark).
  private var themeSelector: some View {
    HStack(spacing: Spacing.s) {
      ForEach(ThemePreference.allCases) { theme in
        optionCard(
          label: theme.label,
          isSelected: preferences.theme == theme,
          action: { withAnimation(Motion.pop) { preferences.theme = theme } }
        ) {
          Image(systemName: themeGlyph(theme))
            .font(.system(size: 22))
        }
      }
    }
  }

  private func themeGlyph(_ theme: ThemePreference) -> String {
    switch theme {
    case .system: "circle.lefthalf.filled"
    case .light: "sun.max.fill"
    case .dark: "moon.stars.fill"
    }
  }

  /// Language stays compact: a labeled row with a trailing menu, since four
  /// options (including non-Latin labels) would crowd a card row.
  private var languageRow: some View {
    HStack {
      Text("Language")
        .font(Typography.body)
      Spacer()
      Menu {
        Picker("Language", selection: languageBinding) {
          ForEach(LanguagePreference.allCases) { language in
            Text(language.label).tag(language)
          }
        }
      } label: {
        HStack(spacing: Spacing.xs) {
          Text(preferences.language.label)
          Image(systemName: "chevron.up.chevron.down")
            .font(.caption2)
        }
        .font(Typography.metadata)
        .foregroundStyle(.secondary)
      }
    }
  }

  private var languageBinding: Binding<LanguagePreference> {
    Binding(get: { preferences.language }, set: { preferences.language = $0 })
  }

  // MARK: - Customization

  private var customizationSection: some View {
    sectionCard("Customization") {
      NavigationLink {
        ReadingOverridesView()
      } label: {
        HStack(spacing: Spacing.m) {
          Image(systemName: "character.book.closed")
            .font(.body)
            .foregroundStyle(Color.accentColor)
            .frame(width: 28)
          Text("Reading Overrides")
            .font(Typography.body)
          Spacer(minLength: 0)
          Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }
  }

  // MARK: - Account

  private var accountSection: some View {
    sectionCard("Account") {
      Button(role: .destructive) {
        Task { await auth.signOut() }
      } label: {
        Text("Sign Out")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .tint(.red)
      .controlSize(.large)
    }
  }

  // MARK: - Provider switching

  /// Tapping a provider switches `MusicState` to it (tearing the previous adapter
  /// down exactly once) and immediately connects it — there is no separate
  /// connect step. `select` is a no-op when the provider is already active, so a
  /// tap on a selected-but-disconnected provider just retries the connect.
  /// Connecting is also what brings player-state observation live (e.g. Apple
  /// Music's `MusicKitAdapter.startObserving`), so auto-connecting on tap is what
  /// keeps the transport and lyrics highlight responsive; Spotify's connect
  /// bounces out to the Spotify app for authorization.
  private func selectProvider(_ provider: MusicProvider) {
    // Already the connected provider — nothing to do.
    if music.activeProvider == provider && music.isConnected { return }
    connectError = nil
    Task {
      await music.select(provider)
      await connectActiveProvider()
    }
  }

  private func connectActiveProvider() async {
    isConnecting = true
    connectError = nil
    let result = await music.connect()
    isConnecting = false
    if case let .failure(error) = result {
      // `notInstalled` → "Spotify isn't installed."; silent reasons
      // (userCancelled / cancelled) leave the row untouched.
      connectError = error.userMessage
    }
  }
}
