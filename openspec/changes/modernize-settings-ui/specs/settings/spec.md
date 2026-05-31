## ADDED Requirements

### Requirement: Settings presented in the design language

The Settings tab SHALL render in the app's Liquid Glass design language rather
than as a stock grouped `Form`. It SHALL keep a pinned hero title in
`Typography.pageTitle` ("Settings") at the same top offset as the Library hero,
and below it SHALL present its content as a vertically-scrolling stack of
section groups. Each section group SHALL be a `Surface`-backed content card
(opaque material, `Radii.lg`) introduced by a `SectionHeader` rendered in
rounded section-title type. The screen SHALL sit over a subtle, brand-aligned
background base that stays legible in both light and dark appearance and under
Reduce Transparency. Spacing, radii, and type SHALL come from the existing
design tokens, and the controls SHALL compose existing primitives rather than
declaring stock `Form`/`Section` chrome.

#### Scenario: Settings renders as composed section cards

- **WHEN** the user opens the Settings tab
- **THEN** the "Settings" hero title is shown over a vertical scroll of
  `Surface`-backed cards titled "Music", "Appearance", "Customization", and an
  account section, with no stock grouped-`Form` styling

#### Scenario: Legible across appearance and Reduce Transparency

- **WHEN** the Settings tab is viewed in light or dark appearance, or with Reduce
  Transparency enabled
- **THEN** the background base and section cards remain legible and the
  active-selection states stay distinguishable

### Requirement: Visual theme selector

The Appearance section SHALL present the theme preference as a visual selector of
the three `ThemePreference` cases (System, Light, Dark), each shown as a
selectable item with a representative glyph and its label, laid out as a row of
equal-width columns. The currently-selected theme SHALL be emphasized with the
brand accent AND a filled, bordered card state (the highlight, not a checkmark)
so the selection is distinguishable without relying on color alone. Selecting an
item SHALL update
`PreferencesState.theme`, and the persistence and live application of the theme
SHALL be unchanged from the existing behavior.

#### Scenario: Selecting a theme

- **WHEN** the user taps the "Dark" item in the theme selector
- **THEN** `PreferencesState.theme` becomes `.dark`, the "Dark" column shows the
  accent-tinted filled/bordered highlight, and the app applies and persists the
  dark theme as before

#### Scenario: Current theme is indicated on open

- **WHEN** the Settings tab opens with the theme set to System
- **THEN** the "System" item is shown in the selected state and the other two are
  not

### Requirement: Language preference control

The Appearance section SHALL let the user choose among the `LanguagePreference`
cases (System, English, 日本語, 中文) using a compact control that shows the
current selection. Choosing a language SHALL update `PreferencesState.language`,
with persistence unchanged from the existing behavior.

#### Scenario: Changing the language

- **WHEN** the user opens the language control and chooses "日本語"
- **THEN** `PreferencesState.language` becomes `.ja` and the control reflects the
  new selection, persisting it as before

### Requirement: Visual provider picker

The Music section SHALL present the music providers from
`MusicState.availableProviders` as a row of equal-width selectable columns —
sharing the theme selector's layout — each showing the provider's brand icon and
display name, rather than a stock `Picker`. A column SHALL show the accent-tinted
filled, bordered highlight (the same indicator as the theme selector, not a
checkmark) only while that provider is the currently-connected one — i.e. when
`MusicState.activeProvider` equals it AND `MusicState.isConnected` is true. When
no provider is connected, no column SHALL be highlighted.

#### Scenario: Connected provider is highlighted

- **WHEN** Spotify is the active provider and `MusicState.isConnected` is true
- **THEN** the Spotify column shows the accent-tinted filled/bordered highlight
  and the other columns do not

#### Scenario: Nothing connected, nothing highlighted

- **WHEN** no provider is connected (none selected, or the active one is not yet
  connected)
- **THEN** no provider column shows the highlighted state

### Requirement: Tapping a provider connects it

Tapping a provider column SHALL select that provider and immediately connect it;
there SHALL be no separate connect/disconnect controls and no connection-state
badge. The tap SHALL clear any prior connect error, call `MusicState.select(_:)`
(a no-op when the provider is already active, so tapping a selected-but-
disconnected provider just retries the connect), and then invoke the connect
flow on the active provider. Tapping the already-connected provider SHALL be a
no-op. While a connect is in flight the tapped column SHALL show a progress
indicator, and on failure the error's `userMessage` SHALL be surfaced as
secondary caption text below the grid (silent reasons such as user-cancelled
leaving it untouched).

#### Scenario: Tapping a disconnected provider connects it

- **WHEN** the user taps the Spotify column while Spotify is not connected
- **THEN** any prior connect error is cleared, `MusicState.select(.spotify)` is
  invoked (when not already active) followed by the connect flow, the column
  shows a progress indicator while connecting, and on success the column becomes
  highlighted

#### Scenario: Connect failure surfaces a note

- **WHEN** tapping a provider's connect fails with a non-silent error
- **THEN** the error's `userMessage` is shown as secondary caption text below the
  provider grid, while silent (user-cancelled) reasons leave the grid unchanged

#### Scenario: Tapping the connected provider does nothing

- **WHEN** the user taps the column of the provider that is already connected
- **THEN** no select or connect is invoked and the highlight is unchanged

### Requirement: Customization and account actions

The Settings tab SHALL present a Customization entry that navigates to
`ReadingOverridesView`, rendered as a tappable card row with a leading glyph and a
trailing chevron affordance. It SHALL present a Sign Out action as a distinct,
clearly-destructive full-width control that invokes `AuthService.signOut()`. The
destinations and actions SHALL be unchanged from the existing behavior; only their
presentation changes.

#### Scenario: Navigate to Reading Overrides

- **WHEN** the user taps the "Reading Overrides" row
- **THEN** `ReadingOverridesView` is pushed onto the navigation stack

#### Scenario: Sign out

- **WHEN** the user taps "Sign Out"
- **THEN** `AuthService.signOut()` is invoked, ending the session as before
