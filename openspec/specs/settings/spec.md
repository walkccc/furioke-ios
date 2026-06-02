## Purpose

TBD - created by archiving change modernize-settings-ui. Update Purpose after
archive.

## Requirements

### Requirement: Signed-in profile header

The Settings tab SHALL present an account header at the top of its scroll, above
the first section group, rendered as a `Surface`-backed card (opaque material,
`Radii.lg`) in the same inset card treatment as the section groups. For a
permanent account, the header SHALL show an avatar disc bearing the user's
initial — derived from the first character of the user's email, upper-cased —
alongside the user's email and a "Signed in" caption in secondary type; when the
email is unavailable it SHALL fall back to a person glyph and omit the email
line while still showing the "Signed in" caption. For a guest (anonymous)
session, the header SHALL instead present a guest state — a person glyph, a
"Browsing as guest" caption, and a clear **Sign in** affordance that opens the
in-app sign-in prompt — and SHALL NOT show a Sign Out action. The identity
portion of the header SHALL be non-interactive (display only) and SHALL read its
data from `AuthService` rather than performing any network fetch. The email
SHALL be truncated to a single line.

#### Scenario: Header shows the signed-in user

- **WHEN** the Settings tab opens while signed in to a permanent account whose
  email is `jay@example.com`
- **THEN** the account header card shows an avatar disc with the initial "J",
  the email `jay@example.com` on a single line, and a "Signed in" caption

#### Scenario: Email unavailable

- **WHEN** the Settings tab opens while signed in to a permanent account but the
  user's email is unavailable
- **THEN** the account header shows a person glyph in the avatar disc and the
  "Signed in" caption, with no email line, and remains legible

#### Scenario: Guest header offers sign-in

- **WHEN** the Settings tab opens while in a guest (anonymous) session
- **THEN** the account header shows a person glyph, a "Browsing as guest"
  caption, and a **Sign in** affordance that opens the in-app sign-in prompt,
  and no Sign Out action is shown

### Requirement: Settings presented in the design language

The Settings tab SHALL render in the app's Liquid Glass design language rather
than as a stock grouped `Form`. It SHALL keep a pinned hero title in
`Typography.pageTitle` ("Settings") at the same top offset as the Library hero,
and below it SHALL present its content as a vertically-scrolling stack
consisting of a profile header card followed by section groups. Each section
group SHALL be a floating, inset `Surface`-backed content card (opaque material,
`Radii.lg`), inset from the screen's horizontal edges, introduced by a
`SectionHeader` rendered in rounded section-title type and sitting above its
card. Within a card, multiple rows SHALL be separated by hairline dividers so
the card reads as one grouped unit, and labeled navigational/action rows SHALL
carry a leading rounded icon tile (a tinted SF Symbol on a `Radii.md` square).
The screen SHALL sit over a subtle, brand-aligned background base that stays
legible in both light and dark appearance and under Reduce Transparency, with
the cards remaining distinguishable from that base. Spacing, radii, and type
SHALL come from the existing design tokens, and the controls SHALL compose
existing primitives rather than declaring stock `Form`/`Section` chrome.

#### Scenario: Settings renders as inset cards under a profile header

- **WHEN** the user opens the Settings tab
- **THEN** the "Settings" hero title is shown over a vertical scroll that begins
  with a profile header card (with the Sign Out action folded in) and continues
  with floating inset `Surface` cards titled "Music", "Appearance", and
  "Customization", with no stock grouped-`Form` styling

#### Scenario: Legible across appearance and Reduce Transparency

- **WHEN** the Settings tab is viewed in light or dark appearance, or with
  Reduce Transparency enabled
- **THEN** the background base, the inset cards, and the active-selection states
  remain legible and distinguishable from one another

### Requirement: Visual theme selector

The Appearance section SHALL present the theme preference as a visual selector
of the three `ThemePreference` cases (System, Light, Dark), each shown as a
selectable item with a representative glyph and its label, laid out as a row of
equal-width columns. The currently-selected theme SHALL be emphasized with the
brand accent AND a filled, bordered card state (the highlight, not a checkmark)
so the selection is distinguishable without relying on color alone. Selecting an
item SHALL update `PreferencesState.theme`, and the persistence and live
application of the theme SHALL be unchanged from the existing behavior.

#### Scenario: Selecting a theme

- **WHEN** the user taps the "Dark" item in the theme selector
- **THEN** `PreferencesState.theme` becomes `.dark`, the "Dark" column shows the
  accent-tinted filled/bordered highlight, and the app applies and persists the
  dark theme as before

#### Scenario: Current theme is indicated on open

- **WHEN** the Settings tab opens with the theme set to System
- **THEN** the "System" item is shown in the selected state and the other two
  are not

### Requirement: Language preference control

The Appearance section SHALL let the user choose among the `LanguagePreference`
cases (System, English, 日本語, 中文) using a compact control that shows the
current selection. Choosing a language SHALL update `PreferencesState.language`,
with persistence unchanged from the existing behavior.

#### Scenario: Changing the language

- **WHEN** the user opens the language control and chooses "日本語"
- **THEN** `PreferencesState.language` becomes `.ja` and the control reflects
  the new selection, persisting it as before

### Requirement: Native language preference control

The Settings Appearance section SHALL let the user choose a **Native language**
— the language learner-facing explanations appear in — independently of the app
language. The control SHALL offer exactly English and 中文 (Traditional
Chinese), shown as a compact control reflecting the current selection. Choosing
a native language SHALL update a persisted `PreferencesState.nativeLanguage`
preference, stored under its own key independent of the app-language key. On
first run, when no native language has been stored, the default SHALL be derived
from the app language: Chinese (explicit `中文`, or `system` resolving to a
Chinese device language) defaults to 中文, and every other app language defaults
to English. The native language SHALL NOT affect the interface `locale`.

#### Scenario: Choosing a native language

- **WHEN** the user opens the Native language control and chooses 中文
- **THEN** `PreferencesState.nativeLanguage` becomes the Chinese case, the
  selection is persisted, and the interface `locale` is unchanged

#### Scenario: Default derived from a Chinese app language

- **WHEN** a user has no stored native language and the app language is `中文`
  (or `system` on a Chinese device)
- **THEN** the native language defaults to 中文

#### Scenario: Default derived from a non-Chinese app language

- **WHEN** a user has no stored native language and the app language is
  English, 日本語, or `system` on a non-Chinese device
- **THEN** the native language defaults to English

#### Scenario: Japanese UI with Chinese explanations

- **WHEN** the app language is 日本語 and the native language is 中文
- **THEN** the interface renders in Japanese AND the translation target is
  `zh-tw`

### Requirement: Visual provider picker

The Music section SHALL present the music providers from
`MusicState.availableProviders` as a row of equal-width selectable columns —
sharing the theme selector's layout — each showing the provider's brand icon and
display name, rather than a stock `Picker`. A column SHALL show the
accent-tinted filled, bordered highlight (the same indicator as the theme
selector, not a checkmark) only while that provider is the currently-connected
one — i.e. when `MusicState.activeProvider` equals it AND
`MusicState.isConnected` is true. When no provider is connected, no column SHALL
be highlighted.

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
- **THEN** the error's `userMessage` is shown as secondary caption text below
  the provider grid, while silent (user-cancelled) reasons leave the grid
  unchanged

#### Scenario: Tapping the connected provider does nothing

- **WHEN** the user taps the column of the provider that is already connected
- **THEN** no select or connect is invoked and the highlight is unchanged

### Requirement: Customization and account actions

The Settings tab SHALL present a Customization entry that navigates to
`ReadingOverridesView`, rendered as a tappable card row with a leading icon tile
and a trailing chevron affordance. The account header card SHALL present a
session action appropriate to the current session: for a permanent account, a
clearly-destructive full-width **Sign Out** row (a red label with a leading icon
tile, below a hairline divider separating it from the identity details) that
invokes `AuthService.signOut()`; for a guest, a **Sign in** affordance that
opens the in-app sign-in prompt. The Customization destination SHALL be
unchanged from the existing behavior; only the presentation and the
guest/permanent split change.

#### Scenario: Navigate to Reading Overrides

- **WHEN** the user taps the "Reading Overrides" row
- **THEN** `ReadingOverridesView` is pushed onto the navigation stack

#### Scenario: Sign out

- **WHEN** a permanent-account user taps the destructive "Sign Out" row in the
  account header card
- **THEN** `AuthService.signOut()` is invoked, ending the permanent session and
  returning the app to a guest session (per the `auth` spec)

#### Scenario: Guest signs in from Settings

- **WHEN** a guest taps the **Sign in** affordance in the account header card
- **THEN** the in-app sign-in prompt is presented with Apple and Google options,
  and completing it upgrades the guest in place to a permanent account

### Requirement: Translation target derived from language preference

The translation target SHALL be derived from the **Native language** preference,
not the app language. The target is the string used as the target language for
learner-facing translation and gloss fetches (Now Playing lyric translation and
flashcard glosses). `NativeLanguagePreference` SHALL expose a
`translationTarget` string: English resolves to `en` and 中文 resolves to
`zh-tw`. `PreferencesState` SHALL expose a single `translationTarget` accessor
delegating to the native language, and every consumer SHALL read the target from
it. The app language (interface `locale`) SHALL NOT influence the translation
target. Japanese SHALL never be a translation target.

#### Scenario: English native language

- **WHEN** the native language is English
- **THEN** `translationTarget` is `"en"`

#### Scenario: Chinese native language

- **WHEN** the native language is 中文
- **THEN** `translationTarget` is `"zh-tw"`

#### Scenario: App language does not change the target

- **WHEN** the native language is English and the app language is changed
  between System, English, 日本語, and 中文
- **THEN** `translationTarget` stays `"en"` across every app-language change

### Requirement: Replay Tutorial action

The Settings Customization section SHALL present a "Replay Tutorial" action row,
rendered in the same labeled-row idiom as the other Customization rows (a
leading icon tile + title). Triggering it SHALL re-present the first-launch
onboarding flow by clearing `PreferencesState.hasCompletedOnboarding` (see the
`onboarding` spec). The row SHALL be available to both guest and permanent
sessions.

#### Scenario: Replay Tutorial re-presents onboarding

- **WHEN** the user taps the "Replay Tutorial" row in the Settings Customization
  section
- **THEN** `PreferencesState.hasCompletedOnboarding` is cleared and the
  onboarding flow is presented again from the welcome screen

#### Scenario: Available to guests

- **WHEN** a guest (anonymous) session opens Settings
- **THEN** the "Replay Tutorial" row is present and functional, with no sign-in
  required
