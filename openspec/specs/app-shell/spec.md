## Purpose

Defines the Furioke iOS app's native SwiftUI shell: the app entry point and iOS
26 deployment target, the sign-in gate that swaps between a full-screen sign-in
surface and the signed-in `AppShell`, and the three-tab navigation (Library,
Search, Settings). It establishes the native Liquid Glass chrome-vs- content
split, the persistent mini-player above the tab bar with its expansion state
machine and one-time onboarding hint, and the system-following theme and
language preferences with explicit overrides. It also specifies the Library
tab's saved-song collection, including tap-to-play and empty-state behavior.

## Requirements

### Requirement: SwiftUI app entry point and deployment target

The iOS app SHALL be a native SwiftUI application with deployment target iOS
26.0 or later. The app SHALL declare a single `App` entry point and SHALL NOT
bundle a web-view-based primary surface.

#### Scenario: Build configuration targets iOS 26+

- **WHEN** the Xcode project is inspected
- **THEN** the deployment target is iOS 26.0 or later, the primary target is the
  iPhone idiom, and no `WKWebView` is used to render the Library, NowPlaying,
  Search, or Settings surfaces

#### Scenario: App launches into native UI

- **WHEN** the user launches the app from the iPhone home screen
- **THEN** the first frame the user sees is rendered by SwiftUI, not by an
  embedded web view

### Requirement: Sign-in gate

The app SHALL be usable without signing in. When no session is present in the
Keychain on launch, the app SHALL bootstrap an anonymous guest session (see the
`guest-session` and `auth` specs) and present the `AppShell` — it SHALL NOT
present a full-screen sign-in wall. The `AppShell` SHALL render identically for
a guest (anonymous) and a permanent account; the two differ only in which
reserved features are gated. The app SHALL present a brief loading surface only
while the initial session restore and any anonymous bootstrap are in flight.
Sign-in SHALL be offered as an in-app prompt (from Settings or when a reserved
feature is invoked), not as a precondition for entering the app.

#### Scenario: Launch with no session lands in AppShell

- **WHEN** the user launches the app and no session is present in the Keychain
- **THEN** the app bootstraps an anonymous guest session and shows the
  `AppShell` with the Library tab selected — no sign-in screen is shown

#### Scenario: Loading surface only during bootstrap

- **WHEN** the initial session restore and anonymous bootstrap are still in
  flight at launch
- **THEN** a brief loading surface is shown, replaced by the `AppShell` once a
  session (guest or permanent) is active

#### Scenario: Sign-in is an in-app upgrade, not a gate

- **WHEN** a guest chooses to sign in (from Settings or a reserved-feature
  prompt) and completes it
- **THEN** the session upgrades to a permanent account in place and the user
  stays in `AppShell` — no app restart and no intervening sign-in wall

### Requirement: AppShell with four primary tabs

The app SHALL present an `AppShell` containing a `TabView` with exactly four
primary tabs in this order: **Library**, **Search**, **Study**, **Settings**,
for both guest and permanent sessions. **Library** SHALL be the default selected
tab on first launch. The **Study** tab SHALL host the flashcard deck and study
mode as a `NavigationStack`. NowPlaying SHALL NOT be a tab — it is delivered as
the expanded state of the persistent mini-player.

#### Scenario: First launch shows Library

- **WHEN** a user (guest or permanent) opens the app for the first time
- **THEN** the Library tab is selected and shown

#### Scenario: Tab order is fixed

- **WHEN** the user views the tab bar
- **THEN** the tabs appear in the order Library, Search, Study, Settings, with
  no user-configurable reordering in v1, and there is no NowPlaying tab

#### Scenario: Study tab hosts the flashcard deck

- **WHEN** the user selects the Study tab
- **THEN** the flashcard deck view is shown, from which study mode can be
  entered (subject to the permanent-account gate for guests, per the
  `flashcards` spec)

#### Scenario: Per-tab scroll state survives switching

- **WHEN** the user scrolls partway through the Library tab, switches to Search,
  and switches back
- **THEN** the Library tab returns to the same scroll position; tab state is not
  reset on switch

### Requirement: Native Liquid Glass adoption with chrome-vs-content split

The app SHALL adopt SwiftUI's native iOS 26 Liquid Glass APIs (`.glassEffect()`
and `GlassEffectContainer`) for chrome surfaces — tab bar, mini-player,
NowPlayingSheet header, provider chips, sign-in button. Chrome SHALL be
distinguished from content: feature views, forms, dialogs, and dense menus SHALL
stay on opaque materials (`Surface`, system Form, popover material). Misuse
SHALL fail at the call site — the `GlassChrome` primitive only accepts `Glass`
role tokens and the `Surface` primitive only accepts opaque `Material` tokens.

#### Scenario: Tab bar uses native glass

- **WHEN** the tab bar renders over scrolling content
- **THEN** the tab bar's translucent background is the system Liquid Glass
  treatment, not a custom blur stack

#### Scenario: Refraction-only, not lightening

- **WHEN** content scrolls behind a Liquid Glass chrome surface
- **THEN** the chrome refracts the underlying content without applying a
  lightening veil that would shift the apparent opacity of content beneath it
  (the same rule the web app's chrome follows for the same reason)

#### Scenario: Forms stay on opaque content surface

- **WHEN** the Settings tab, override editor sheet, or any destructive- confirm
  dialog renders
- **THEN** it uses the opaque `Surface` / `Form` material, not glass — glass is
  reserved for chrome with a refractable backdrop

### Requirement: Persistent mini-player above the tab bar

`AppShell` SHALL host a persistent `MiniPlayer` above the tab bar via the iOS 26
`tabViewBottomAccessory` API. The mini-player SHALL be visible whenever a track
is loaded against the active provider, including paused state. The mini-player
SHALL be hidden when no track has been loaded this session OR when the user is
not connected to any provider.

#### Scenario: Mini-player appears on first play

- **WHEN** the user plays a track from Library or Search and the active provider
  is connected
- **THEN** the mini-player appears above the tab bar, showing the artwork,
  title, artist, and play / next transport buttons

#### Scenario: Mini-player persists when paused

- **WHEN** the user pauses playback from the mini-player or NowPlayingSheet
- **THEN** the mini-player remains visible — only the play / pause glyph changes

#### Scenario: Mini-player hides on disconnect

- **WHEN** the user disconnects the active provider in Settings
- **THEN** the mini-player disappears from the chrome on the next render

### Requirement: Mini-player expansion state machine

Mini-player → NowPlayingSheet expansion SHALL be driven by a state machine with
phases `collapsed → expanding → expanded → collapsing → collapsed`. Inputs SHALL
be ignored in the two transitional phases so rapid drag / dismiss cycles do not
interleave matched-geometry animations.

#### Scenario: Tap or drag-up expands

- **WHEN** the user taps the mini-player or drags up past the activation
  threshold
- **THEN** the state machine transitions to `expanding` and presents
  `NowPlayingSheet`; once the sheet finishes its appear animation the state is
  `expanded`

#### Scenario: Chevron or drag-down collapses

- **WHEN** the user taps the chevron-down in the NowPlayingSheet header or drags
  the sheet down past the dismiss threshold
- **THEN** the state machine transitions to `collapsing` then `collapsed`, and
  the sheet dismisses with the matched-geometry artwork / title / artist
  morphing back into the mini-player

#### Scenario: Inputs ignored mid-transition

- **WHEN** the user double-taps the mini-player rapidly during the `expanding`
  phase
- **THEN** the second tap is ignored — only `collapsed → expanding` is honored

### Requirement: One-time onboarding hint

The app SHALL display a one-time onboarding hint the first time a track lands in
the persistent mini-player on a given device, pointing at the mini-player with
copy explaining the tap-to-open affordance. The hint SHALL dismiss when the user
taps the mini-player, taps the hint's close affordance, or after the sheet has
been expanded once. The hint SHALL NOT reappear on subsequent launches.

#### Scenario: First-ever play surfaces the hint

- **WHEN** a track lands in the mini-player for the first time on this device
- **THEN** a hint anchored above the tab bar appears with copy directing the
  user to tap the mini-player

#### Scenario: Hint dismisses on first interaction

- **WHEN** the user taps the mini-player or the hint's close affordance
- **THEN** the hint dismisses immediately and persists as dismissed via
  `@AppStorage`

#### Scenario: Hint does not return

- **WHEN** the user closes the app and re-launches it after the hint has been
  shown and dismissed once
- **THEN** the hint does not reappear

### Requirement: Theme follows system, with explicit override available

The app SHALL follow the system appearance (light or dark) by default. The user
SHALL be able to override to **Light**, **Dark**, or **System** from the
Settings tab. The preference SHALL persist in `UserDefaults` and SHALL apply on
every subsequent app launch.

#### Scenario: System theme by default

- **WHEN** a new user installs the app and the device is in dark mode
- **THEN** the app renders in dark mode without any user configuration

#### Scenario: Explicit override persists

- **WHEN** the user selects **Light** in Settings and force-quits the app
- **THEN** on next launch the app renders in light mode regardless of the system
  setting

### Requirement: Language follows system, with explicit override available

The app SHALL follow the system locale for UI strings, supporting **en**,
**ja**, and **zh**. The user SHALL be able to override to a specific language
from the Settings tab. The preference SHALL persist in `UserDefaults`.

#### Scenario: System locale by default

- **WHEN** a Japanese-language device launches the app for the first time
- **THEN** the app's UI strings render in Japanese

#### Scenario: Explicit language override

- **WHEN** the user selects **English** in Settings on a Japanese device
- **THEN** the app immediately re-renders UI strings in English and uses English
  on subsequent launches

### Requirement: Library tab shows the saved-song collection

For a permanent account, the Library tab SHALL display the user's saved songs
from `songs`, ordered most-recently-saved first, each row rendered via the
shared `RowItem` primitive. Tapping a song SHALL call
`NowPlayingState.play(track:)` and SHALL request expansion of the persistent
mini-player into `NowPlayingSheet`. The Library tab SHALL present an empty-state
surface (`EmptyState` primitive) when a permanent account has no saved songs,
with copy directing them to Search or to playing a track in their connected
provider. For a guest (anonymous) session, which cannot persist a Library, the
Library tab SHALL present a sign-in empty-state inviting the user to sign in to
save songs, with a sign-in entry point, instead of a song list.

#### Scenario: Library lists saved songs

- **WHEN** a permanent-account user with saved songs opens the Library tab
- **THEN** the list shows their saved songs ordered by save time, most recent
  first, each row rendered with `RowItem` displaying artwork, title, and artist

#### Scenario: Tap expands NowPlayingSheet

- **WHEN** the user taps a song in the Library
- **THEN** `NowPlayingState.play(track:)` is invoked, the lyric fetch begins,
  and the persistent mini-player expands into `NowPlayingSheet` via the shared
  matched-geometry namespace — the active tab does not change

#### Scenario: Empty-state library

- **WHEN** a permanent-account user with zero saved songs opens the Library tab
- **THEN** an `EmptyState` card renders with copy explaining how to add songs
  (via Search or by playing a track in the connected provider, then tapping Save
  in NowPlayingSheet)

#### Scenario: Guest sees a sign-in empty state

- **WHEN** a guest (anonymous) session opens the Library tab
- **THEN** the tab shows a sign-in empty-state explaining that saving songs
  requires an account, with a sign-in entry point, rather than a song list

### Requirement: First-launch onboarding presentation

`AppShell` SHALL present the first-launch onboarding flow (see the `onboarding`
spec) as a full-screen cover over the shell, gated by the persisted
`PreferencesState.hasCompletedOnboarding` flag: the cover SHALL be presented
while the flag is `false` and SHALL NOT be presented once it is `true`. The
cover SHALL be presented for both guest and permanent sessions and SHALL NOT
replace the guest-first launch behavior — the shell still renders beneath the
cover, so dismissing onboarding (via complete or skip) reveals the
already-loaded `AppShell` with the Library tab selected, with no app restart.
This presentation is distinct from, and does not affect, the existing one-time
mini-player onboarding hint.

#### Scenario: Onboarding cover over the shell on first launch

- **WHEN** the app launches into the `AppShell` and `hasCompletedOnboarding` is
  `false`
- **THEN** `AppShell` presents the onboarding flow as a full-screen cover above
  the shell, while the shell itself remains mounted beneath it

#### Scenario: Dismissing reveals the shell without restart

- **WHEN** the user completes or skips onboarding
- **THEN** the cover dismisses, `hasCompletedOnboarding` is `true`, and the
  already-mounted `AppShell` is revealed on the Library tab with no app restart

#### Scenario: No cover once completed

- **WHEN** the app launches and `hasCompletedOnboarding` is `true`
- **THEN** `AppShell` does not present the onboarding cover and the existing
  mini-player onboarding hint behavior is unchanged
