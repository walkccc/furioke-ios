import SwiftUI

/// Settings: music-provider selection + connect / disconnect, language and
/// theme preferences, and sign out. The provider picker switches the active
/// provider (tearing the previous one down); connect / disconnect then act on
/// whichever provider is selected.
///
/// Rendered in the app's design language as a liquid-glass surface: a pinned
/// liquid-glass hero bar that the scroll passes translucently beneath, over a
/// vertical scroll that opens with a profile header and continues with grouped
/// inset cards, each introduced by a `SectionHeader`.
/// The cards float as `.glassEffect` panes over an atmospheric sage/amber
/// backdrop so the glass has a living, brand-tinted backdrop to refract — the
/// thing that actually sells the liquid-glass feel. Account actions live inline
/// in the profile card at the very top of the scroll, so they sit in one
/// consistent, no-scroll position across states: a guest gets a trailing
/// "Sign In" capsule, a signed-in user gets a trailing menu holding Sign Out and
/// a destructive Delete Account (the latter gated behind a confirmation dialog).
///
/// Legibility is preserved under Reduce Transparency: the backdrop is pure
/// colour, and the glass card panes fall back to opaque `contentSurface`
/// material — keeping faith with the chrome-vs-content split while still
/// presenting glass by default.
struct SettingsView: View {
  @Environment(AuthService.self) private var auth
  @Environment(PreferencesState.self) private var preferences
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  /// Drives the two-step Delete Account flow: the trailing menu arms the
  /// confirmation dialog, the dialog performs the (irreversible) delete, and a
  /// failure surfaces in `deleteError`. `isDeleting` swaps the menu glyph for a
  /// spinner so the in-flight delete reads while the network call runs.
  @State private var isConfirmingDelete = false
  @State private var isDeleting = false
  @State private var deleteError: String?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: Spacing.l) {
          profileHeader
          musicSection
          languageSection
          customizationSection
          communitySection
          // Theme sits last among the cards: it's the least consequential
          // preference, so it floats below the more frequently used sections.
          themeSection
        }
        .padding(.top, Spacing.xs)
        .padding(.bottom, Spacing.xl)
      }
      // The hero title is pinned over the scroll as a liquid-glass chrome bar via
      // `safeAreaInset`: cards rest below it at first, but scroll up *behind* it,
      // so the glass refracts the content sliding underneath — the translucent
      // header feel. The inset reserves the bar's height so nothing starts hidden.
      .safeAreaInset(edge: .top, spacing: 0) {
        pageHeader
      }
      // An atmospheric brand backdrop: soft sage + warm radial washes over the
      // grouped-background tone, giving the glass card panes a living, tinted
      // surface to refract. Pure colour, so it stays legible under Reduce
      // Transparency and matches the seamless strip the pinned hero needs.
      .background(backgroundBase)
      // The custom hero title replaces the system large title.
      .toolbar(.hidden, for: .navigationBar)
    }
  }

  // MARK: - Header

  /// The pinned hero title rendered as a liquid-glass chrome bar. The title
  /// content stays within the safe area, while its glass background bleeds up
  /// under the status bar (`ignoresSafeArea` lives on the background layer only),
  /// so content scrolling beneath refracts through the full strip rather than
  /// popping in below a hard edge.
  private var pageHeader: some View {
    PageTitle(title: "Settings")
      .background { headerBackground }
  }

  /// The header's surface: the see-through `.clear` glass (the same variant the
  /// cards use), so the atmospheric backdrop reads straight through and the bar
  /// keeps its original colour at rest — content only gains a soft translucent
  /// refraction as it scrolls underneath, with no hard edge defining the bar.
  ///
  /// The glass is masked with a top-to-bottom gradient that fades its lower edge
  /// to nothing, so the rectangle's specular bottom border dissolves into the
  /// backdrop instead of drawing a hard hairline across the screen — the strip
  /// reads as a soft translucent wash, not a boxed bar.
  ///
  /// Under Reduce Transparency it falls back to the opaque grouped-background
  /// tone — matching `backgroundBase` so the strip stays seamless and legible,
  /// honouring the chrome-vs-content legibility guarantee.
  @ViewBuilder
  private var headerBackground: some View {
    if reduceTransparency {
      Color(.systemGroupedBackground)
        .ignoresSafeArea(edges: .top)
    } else {
      Color.clear
        .glassEffect(.clear, in: Rectangle())
        .mask(
          LinearGradient(
            colors: [.black, .black, .clear],
            startPoint: .top,
            endPoint: .bottom
          )
        )
        .ignoresSafeArea(edges: .top)
    }
  }

  // MARK: - Background

  /// Layered sage + warm radial washes over the grouped-background tone. With
  /// the panes now using see-through `.clear` glass, the backdrop reads straight
  /// through them — so the washes are richer here than a typical chrome tint,
  /// giving the transparent panes real colour to carry while staying soft enough
  /// to keep card text legible.
  private var backgroundBase: some View {
    ZStack {
      Color(.systemGroupedBackground)
      RadialGradient(
        colors: [Color.accentColor.opacity(0.28), .clear],
        center: .topLeading,
        startRadius: 0,
        endRadius: 480
      )
      RadialGradient(
        colors: [Color.accentColor.opacity(0.16), .clear],
        center: .bottomTrailing,
        startRadius: 0,
        endRadius: 440
      )
      // A warm note in the upper-right and a second sage bloom mid-left keep the
      // glass from reading as a single flat green — the refraction gets more than
      // one hue to play with as you scroll the panes over it.
      RadialGradient(
        colors: [Color.orange.opacity(0.10), .clear],
        center: UnitPoint(x: 0.90, y: 0.10),
        startRadius: 0,
        endRadius: 360
      )
      RadialGradient(
        colors: [Color.accentColor.opacity(0.10), .clear],
        center: UnitPoint(x: 0.10, y: 0.55),
        startRadius: 0,
        endRadius: 320
      )
    }
    .ignoresSafeArea()
  }

  // MARK: - Card container

  /// Side length of the leading icon tile, shared so row dividers can inset to
  /// the text that follows the tile.
  private let iconTileSize: CGFloat = 30

  /// The grouped-inset card pane shared by the profile header and every section:
  /// content padded to `Spacing.l`, then floated as a `Radii.xl` liquid-glass
  /// pane over the atmospheric backdrop.
  ///
  /// The glass is the see-through `.clear` variant (rather than frosted
  /// `.regular`), so the sage/amber backdrop reads straight through the panes for
  /// a lighter, genuinely transparent feel; a hairline top-lit edge defines each
  /// pane against the busy backdrop. Under Reduce Transparency the pane falls
  /// back to opaque `contentSurface` material so it stays fully legible —
  /// honouring the chrome-vs-content split's legibility guarantee.
  @ViewBuilder
  private func cardPane(@ViewBuilder content: () -> some View) -> some View {
    let shape = RoundedRectangle(cornerRadius: Radii.xl, style: .continuous)
    let padded = content()
      .padding(.horizontal, Spacing.l)
      .padding(.vertical, Spacing.l)
      .frame(maxWidth: .infinity, alignment: .leading)
    if reduceTransparency {
      padded.background(OpaqueMaterial.contentSurface.color, in: shape)
    } else {
      padded
        .glassEffect(.clear, in: shape)
        .overlay(
          shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
        )
    }
  }

  /// One section group: a `SectionHeader` label sitting above a floating, inset
  /// glass `cardPane`, inset from the screen edges by `Spacing.l` so it reads as
  /// a grouped-inset unit.
  private func sectionCard(
    _ title: LocalizedStringKey,
    @ViewBuilder content: () -> some View
  ) -> some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      SectionHeader(title)
      cardPane {
        VStack(alignment: .leading, spacing: Spacing.m) {
          content()
        }
      }
      .padding(.horizontal, Spacing.l)
    }
  }

  /// Leading rounded icon tile — a tinted SF Symbol on a `Radii.md` square —
  /// giving labeled rows the contemporary iOS Settings idiom.
  private func iconTile(systemName: String, tint: Color) -> some View {
    RoundedRectangle(cornerRadius: Radii.md, style: .continuous)
      .fill(tint.opacity(0.16))
      .frame(width: iconTileSize, height: iconTileSize)
      .overlay {
        Image(systemName: systemName)
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(tint)
      }
      .accessibilityHidden(true)
  }

  /// Hairline separator for multi-row cards, inset to align with the row content
  /// that follows the leading icon tile so the card reads as one grouped unit.
  private var rowDivider: some View {
    Divider()
      .padding(.leading, iconTileSize + Spacing.m)
  }

  // MARK: - Profile header

  /// Identity card at the top of the scroll, doubling as the account hub: an
  /// avatar disc bearing the signed-in user's initial, their email, and a
  /// "Signed in" caption, with the account action pinned to the trailing edge so
  /// it stays in one no-scroll position across states. Identity reads
  /// `auth.userEmail` (already in memory from the session — no network fetch);
  /// the avatar degrades to a person glyph with no email line when the email is
  /// unavailable.
  private var profileHeader: some View {
    cardPane {
      HStack(spacing: Spacing.m) {
        avatarDisc
        VStack(alignment: .leading, spacing: 2) {
          if let email = auth.userEmail {
            Text(email)
              .font(Typography.body.weight(.semibold))
              .lineLimit(1)
              .minimumScaleFactor(0.7)
          }
          Text(auth.isSignedIn ? "Signed in" : "Browsing as guest")
            .font(Typography.metadata)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(profileAccessibilityLabel)
        Spacer(minLength: Spacing.s)
        accountAffordance
      }
    }
    .padding(.horizontal, Spacing.l)
    .confirmationDialog(
      "Delete Account?",
      isPresented: $isConfirmingDelete,
      titleVisibility: .visible
    ) {
      Button("Delete Account", role: .destructive, action: performDelete)
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "This permanently deletes your account and everything in it — saved songs, flashcards, reading overrides, and preferences. This can't be undone."
      )
    }
    .alert(
      "Couldn't Delete Account",
      isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(deleteError ?? "")
    }
  }

  /// Solid accent disc showing the email's first character upper-cased, or a
  /// person glyph fallback when no email is available. Filled (not a faint tint)
  /// so the avatar stays clearly visible regardless of the accent hue.
  private var avatarDisc: some View {
    Circle()
      .fill(Color.accentColor.gradient)
      .frame(width: 52, height: 52)
      .overlay {
        if let initial = avatarInitial {
          Text(initial)
            .font(.system(.title2, design: .rounded, weight: .semibold))
            .foregroundStyle(.white)
        } else {
          Image(systemName: "person.fill")
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(.white)
        }
      }
      .accessibilityHidden(true)
  }

  // MARK: - Account action

  /// The account action pinned to the trailing edge of the profile card, so it
  /// sits in the same no-scroll position whether or not you're signed in: a
  /// guest gets a prominent "Sign In" capsule opening the shared in-app prompt; a
  /// signed-in user gets a compact menu holding Sign Out and the destructive
  /// Delete Account. While a delete is in flight the menu glyph becomes a spinner.
  @ViewBuilder
  private var accountAffordance: some View {
    if auth.isSignedIn {
      Menu {
        Button {
          Task { await auth.signOut() }
        } label: {
          Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
        }
        Button(role: .destructive) {
          isConfirmingDelete = true
        } label: {
          Label("Delete Account", systemImage: "trash")
        }
      } label: {
        accountMenuGlyph
      }
      .disabled(isDeleting)
      .accessibilityLabel("Account options")
    } else {
      Button("Sign In") {
        auth.presentSignInPrompt()
      }
      .buttonStyle(.glassProminent)
      .controlSize(.small)
      .font(.system(size: 15, weight: .semibold))
    }
  }

  /// The signed-in menu's trailing glyph: an ellipsis at rest, a spinner while
  /// the account delete runs.
  @ViewBuilder
  private var accountMenuGlyph: some View {
    if isDeleting {
      ProgressView()
        .controlSize(.small)
        .frame(width: 30, height: 30)
    } else {
      Image(systemName: "ellipsis.circle")
        .font(.system(size: 24))
        .foregroundStyle(.secondary)
        .frame(width: 30, height: 30)
    }
  }

  /// Runs the irreversible account delete from the confirmation dialog. On
  /// success `AuthService` tears down the session and bootstraps a fresh guest;
  /// a failure surfaces in `deleteError` and leaves the account intact.
  private func performDelete() {
    Task {
      isDeleting = true
      defer { isDeleting = false }
      do {
        try await auth.deleteAccount()
      } catch {
        deleteError = "Something went wrong deleting your account. Please check your connection and try again."
      }
    }
  }

  private var avatarInitial: String? {
    guard let first = auth.userEmail?.first else { return nil }
    return String(first).uppercased()
  }

  private var profileAccessibilityLabel: Text {
    if let email = auth.userEmail {
      Text("Signed in as \(email)")
    } else if auth.isSignedIn {
      Text("Signed in")
    } else {
      Text("Browsing as guest")
    }
  }

  /// Shared three-column option cell used by both selectors: an icon over a
  /// label. The active option is highlighted with an accent fill + ring (the
  /// filled state is the selection indicator — no checkmark, kept minimal).
  private func optionCard(
    label: String,
    isSelected: Bool,
    action: @escaping () -> Void,
    @ViewBuilder icon: () -> some View
  ) -> some View {
    let shape = RoundedRectangle(cornerRadius: Radii.md, style: .continuous)
    return Button(action: action) {
      VStack(spacing: Spacing.xs) {
        icon()
          .frame(height: 30)
        // Theme labels are catalog keys ("System"/"Light"/"Dark") and localize;
        // provider brand names aren't keys, so they fall through verbatim.
        Text(LocalizedStringKey(label))
          .font(Typography.metadata)
          .lineLimit(1)
          .minimumScaleFactor(0.75)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, Spacing.m)
      .foregroundStyle(isSelected ? Color.accentColor : .primary)
      .background(
        // Unselected cells stay barely-there so the transparent pane (and the
        // backdrop behind it) reads through them; the selected cell fills with
        // accent so the choice still pops against the glass.
        shape.fill(isSelected ? Color.accentColor.opacity(0.18) : Color(.quaternarySystemFill))
      )
      .overlay(
        shape.strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
      )
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    .accessibilityLabel(Text(LocalizedStringKey(label)))
  }

  // MARK: - Music

  private var musicSection: some View {
    sectionCard("Music provider") {
      // The shared provider grid (also used by onboarding): self-contained —
      // highlight means connected, tapping connects, and it surfaces its own
      // connect-failure note below the grid.
      ProviderSelector()
    }
  }

  // MARK: - Language

  /// The two language preferences grouped as their own standalone section: the
  /// interface language and the learner's explanation language, separated by a
  /// hairline divider.
  private var languageSection: some View {
    sectionCard("Language") {
      languageRow
      rowDivider
      nativeLanguageRow
    }
  }

  // MARK: - Theme

  /// Theme as its own standalone section. The section header names it, so the
  /// selector needs no inner caption.
  private var themeSection: some View {
    sectionCard("Theme") {
      themeSelector
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

  /// App Language stays compact: a labeled row with a trailing menu, since the
  /// options (including non-Latin labels) would crowd a card row.
  private var languageRow: some View {
    languageMenuRow(
      icon: "translate",
      title: "App Language",
      selectedLabel: preferences.language.label,
      selection: languageBinding,
      options: LanguagePreference.allCases,
      optionLabel: \.label
    )
  }

  private var languageBinding: Binding<LanguagePreference> {
    Binding(get: { preferences.language }, set: { preferences.language = $0 })
  }

  /// The learner's explanation language, separate from the interface language:
  /// it drives translations and flashcard glosses. Same compact labeled-row
  /// shape as `languageRow`.
  private var nativeLanguageRow: some View {
    languageMenuRow(
      icon: "text.bubble",
      title: "Native Language",
      selectedLabel: preferences.nativeLanguage.label,
      selection: nativeLanguageBinding,
      options: NativeLanguagePreference.allCases,
      optionLabel: \.label
    )
  }

  private var nativeLanguageBinding: Binding<NativeLanguagePreference> {
    Binding(get: { preferences.nativeLanguage }, set: { preferences.nativeLanguage = $0 })
  }

  /// The shared compact "label + trailing menu picker" row used by both language
  /// preferences: a leading icon tile, a title, and a menu whose label shows the
  /// current selection with an up/down chevron.
  private func languageMenuRow<Option: Hashable & Identifiable>(
    icon: String,
    title: LocalizedStringKey,
    selectedLabel: String,
    selection: Binding<Option>,
    options: [Option],
    optionLabel: KeyPath<Option, String>
  ) -> some View {
    HStack(spacing: Spacing.m) {
      iconTile(systemName: icon, tint: Color.accentColor)
      Text(title)
        .font(Typography.body)
      Spacer()
      Menu {
        Picker(title, selection: selection) {
          ForEach(options) { option in
            Text(option[keyPath: optionLabel]).tag(option)
          }
        }
      } label: {
        HStack(spacing: Spacing.xs) {
          Text(selectedLabel)
          Image(systemName: "chevron.up.chevron.down")
            .font(.caption2)
        }
        .font(Typography.metadata)
        .foregroundStyle(Color.accentColor)
      }
    }
  }

  // MARK: - Customization

  private var customizationSection: some View {
    sectionCard("Customization") {
      NavigationLink {
        ReadingOverridesView()
      } label: {
        HStack(spacing: Spacing.m) {
          iconTile(systemName: "character.book.closed", tint: Color.accentColor)
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

      rowDivider

      replayTutorialRow
    }
  }

  /// Re-presents the first-launch onboarding flow. Clearing the completion flag
  /// flips the `AppShell` cover back on over the shell.
  private var replayTutorialRow: some View {
    Button {
      preferences.restartOnboarding()
    } label: {
      HStack(spacing: Spacing.m) {
        iconTile(systemName: "graduationcap", tint: Color.accentColor)
        Text("Replay Tutorial")
          .font(Typography.body)
        Spacer(minLength: 0)
        Image(systemName: "arrow.counterclockwise")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(.tertiary)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(.primary)
    .accessibilityLabel("Replay Tutorial")
  }

  // MARK: - Community

  /// The Discord brand blurple, shared by the icon tile so the community row
  /// carries Discord's own colour rather than the app accent.
  private static let discordBlurple = Color(red: 0x58 / 255, green: 0x65 / 255, blue: 0xF2 / 255)

  /// The single source of truth for the community invite, mirroring the web
  /// app's `DISCORD_INVITE_URL`.
  private static let discordInviteURL = URL(string: "https://discord.gg/YaS5yrtg")!

  /// The community section: a single "Join Discord" row that opens the invite in
  /// the browser. A `Link` (not a `Button`) so it reads as an outward navigation
  /// and hands the URL straight to the system, matching the app's other external
  /// links.
  private var communitySection: some View {
    sectionCard("Community") {
      Link(destination: Self.discordInviteURL) {
        HStack(spacing: Spacing.m) {
          discordIconTile
          Text("Join Discord")
            .font(Typography.body)
          Spacer(minLength: 0)
          Image(systemName: "arrow.up.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .foregroundStyle(.primary)
      .accessibilityLabel("Join Discord")
    }
  }

  /// Leading tile for the Discord row: the white Discord glyph on a blurple
  /// rounded square, matching the size of the SF Symbol `iconTile`s while wearing
  /// Discord's brand colour the way iOS Settings renders third-party app rows.
  private var discordIconTile: some View {
    RoundedRectangle(cornerRadius: Radii.md, style: .continuous)
      .fill(Self.discordBlurple)
      .frame(width: iconTileSize, height: iconTileSize)
      .overlay {
        Image("DiscordIcon")
          .renderingMode(.original)
          .resizable()
          .scaledToFit()
          .frame(width: 18, height: 18)
      }
      .accessibilityHidden(true)
  }
}
