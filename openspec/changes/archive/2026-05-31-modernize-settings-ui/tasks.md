## 1. Scaffold the composed layout

- [x] 1.1 In `SettingsView.swift`, replace the grouped `Form` with a
      `ScrollView` containing a `VStack(spacing: Spacing.l)` of section groups,
      keeping the existing pinned hero title ("Settings",
      `Typography.pageTitle`) above the scroll at its current top offset and the
      `NavigationStack` + `.toolbar(.hidden, for: .navigationBar)` intact.
- [x] 1.2 Add the subtle brand-tinted background base
      (`Color(.systemGroupedBackground)` with an optional soft `AccentColor`
      tint) behind both the scroll and the pinned hero so the strip above the
      first card reads seamlessly; confirm it degrades cleanly under Reduce
      Transparency.
- [x] 1.3 Add a private section-card helper: a `SectionHeader("…")` over a
      `Surface(material: .contentSurface, cornerRadius: Radii.lg)` with
      `Spacing.l` inner padding and the existing outer horizontal padding, so
      every section reuses one card shape.

## 2. Appearance section

- [x] 2.1 Build a private theme selector subview: a row of three equal-width
      selectable cards for `ThemePreference.allCases` (glyph + label: System →
      `circle.lefthalf.filled`, Light → `sun.max`, Dark → `moon.stars`).
- [x] 2.2 Wire selection to `preferences.theme` inside
      `withAnimation(Motion.pop)`; show the selected card with an `AccentColor`
      fill/tint AND a non-color indicator (checkmark or filled/bold state) so
      it's distinguishable without color; verify in grayscale.
- [x] 2.3 Keep the language preference as a compact labeled row whose trailing
      control is a `Menu`/inline `.menu` `Picker` over
      `LanguagePreference.allCases`, bound to `preferences.language` and showing
      the current `.label`.

## 3. Music section

- [x] 3.1 Build the provider grid as a three-column selector sharing the theme
      selector's `optionCard` layout, one column per `music.availableProviders`,
      each showing the provider's brand icon (added to `Assets.xcassets` from
      the web `icons/*.tsx` SVG paths) + `displayName`.
- [x] 3.2 Highlight a column only while that provider is connected
      (`music.activeProvider == provider && music.isConnected`); when nothing is
      connected, nothing is highlighted.
- [x] 3.3 Wire the tap to select + auto-connect: no-op if already connected;
      otherwise `connectError = nil`, `await music.select(provider)` (no-op when
      already active), then `await connectActiveProvider()`.
- [x] 3.4 Show a progress indicator on the tapped column while its connect is in
      flight, and surface `connectError` as a `Typography.metadata` caption
      below the grid on failure. No connection badge and no connect/disconnect
      buttons.
- [x] 3.5 Removed: no no-provider guidance branch — the grid is the affordance.

## 4. Customization and account sections

- [x] 4.1 Present Reading Overrides as a card row: a `NavigationLink` to
      `ReadingOverridesView` with a leading `character.book.closed` glyph,
      title, and trailing chevron, styled over the section card.
- [x] 4.2 Present Sign Out as a distinct full-width destructive control in its
      own `Surface` card, invoking `Task { await auth.signOut() }` unchanged.

## 5. Verify

- [ ] 5.1 Build and run; confirm the hero, section cards, theme selector,
      provider chips, connection badge, and actions render as designed.
- [ ] 5.2 Verify behavior parity: theme selection persists and applies live;
      language change persists; selecting Apple Music eagerly connects (player
      observation live) while Spotify stays manual; connect/disconnect and the
      connect-error caption behave as before; Reading Overrides pushes; Sign Out
      ends the session.
- [ ] 5.3 Verify accessibility: selected states are distinguishable in
      grayscale, Dynamic Type scales theme cards / provider chips / language
      label without clipping (wrap or scale at large sizes), and the layout
      stays legible under Reduce Transparency and in both light and dark
      appearance.
- [ ] 5.4 Verify the last card clears the floating mini-player + tab bar (same
      `tabViewBottomAccessory` clearance Library relies on) and the background
      has no seam behind the pinned hero title.
