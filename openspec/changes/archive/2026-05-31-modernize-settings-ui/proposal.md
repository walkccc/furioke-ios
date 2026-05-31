## Why

The app owns a deliberate Liquid Glass design language — rounded display type,
`Surface` cards, `GlassCapsule` chips, tokenized spacing/radii/materials, a sage
brand accent — and Now Playing and the freshly-redesigned Library both speak it.
The Settings tab does not: under its custom hero title it is a stock grouped
`Form` of system `Picker`s, plain `Label`s, and bordered buttons. It reads as
generic iOS sitting next to bespoke chrome, so the one screen users open to make
the app _theirs_ is its least polished surface. This change makes Settings
fluent in the design language the app already owns.

## What Changes

- Replace the grouped `Form`/`Section` stack with a **composed scroll of
  `Surface`-backed section cards**, each headed by a rounded-type
  `SectionHeader` ("Appearance", "Music", "Customization", "Account"), over a
  subtle brand-tinted background base. Keeps the existing pinned hero title.
- Redesign **Appearance** as a **visual theme selector** — three selectable
  cards (System / Light / Dark) with glyphs, the active one accent-tinted —
  replacing the stock theme `Picker`; language stays a compact inline menu.
- Redesign **Music** as a **three-column provider grid** sharing the theme
  selector's layout — each provider shown as its brand icon + name. A column is
  highlighted only while that provider is connected (nothing connected → nothing
  highlighted), and **tapping a provider selects and connects it directly** —
  there is no separate Connect / Disconnect control and no connection badge. A
  connect failure surfaces a small caption below the grid.
- Present **Customization** (Reading Overrides) as a tappable card row with a
  leading glyph and trailing chevron, and **Sign Out** as a distinct,
  clearly-destructive full-width action in its own card.
- **Behavior-preserving (skin + interaction polish only)**: no change to what
  the controls _do_ — provider selection still switches `MusicState` (eager
  Apple Music connect preserved), connect/disconnect, theme/language
  persistence, Reading Overrides navigation, and sign-out all behave exactly as
  today. Only the presentation and the on-screen affordances change.

## Capabilities

### New Capabilities

- `settings`: The Settings tab — presents appearance (theme + language),
  music-provider selection with connect / disconnect and live connection state,
  customization (Reading Overrides), and sign-out, rendered in the app's Liquid
  Glass design language: a pinned hero title over `Surface`-backed section
  cards, a visual theme selector, and a visual provider picker with a
  connection-state badge. (Authors the previously-unspecced Settings
  presentation; the visual treatment is new, the underlying interactions are
  documented as-is.)

### Modified Capabilities

<!-- None. The redesign composes existing design-system primitives (Surface,
     SectionHeader, GlassCapsule, EmptyState, the Typography/Spacing/Radii/
     Materials tokens) without adding or changing any primitive, so the
     `design-system` spec is unchanged. The theme/language persistence,
     auth sign-out, and music connect/disconnect *behaviors* remain specified
     in `app-shell`, `auth`, and `music-source` respectively and are unchanged. -->

## Impact

- **Code**: `Furioke/Features/SettingsView.swift` (rewritten presentation; the
  visual theme selector, provider picker, connection badge, and section cards
  are added as private subviews composing existing primitives).
- **Unaffected**: `PreferencesState` (theme/language + persistence),
  `MusicState` (provider select / connect / disconnect, `availableProviders`,
  `isConnected`), `AuthService.signOut()`, and `ReadingOverridesView` — all
  consumed unchanged. The `providerSelection` binding's switch-and-eager-connect
  logic is preserved.
- **Dependencies**: none added. Reuses existing tokens and primitives only; the
  sage accent already exists as `AccentColor` in the asset catalog.
- **Accessibility**: section cards and selectors must scale with Dynamic Type
  (existing tokens already do) and keep the active-selection state legible
  without relying on color alone (pair the accent tint with a checkmark/label).
  The brand-tinted background must stay legible under Reduce Transparency and in
  both appearances.
