## ADDED Requirements

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

When no Supabase session is present, the app SHALL present a full-screen sign-in
surface in place of the `AppShell`. When a session is present, the app SHALL
present the `AppShell`. The transition between the two states SHALL happen
without an app restart when the session changes during runtime (see
[[ios-auth]]).

#### Scenario: Signed-out user sees sign-in surface

- **WHEN** the user launches the app and no Supabase session is present in the
  Keychain
- **THEN** the app shows a sign-in screen, not the `AppShell`

#### Scenario: Sign-in transitions to AppShell

- **WHEN** a signed-out user completes sign-in successfully
- **THEN** the sign-in surface dismisses and the `AppShell` appears with the
  Library tab selected

#### Scenario: Sign-out returns to sign-in surface

- **WHEN** the user signs out from Settings
- **THEN** the `AppShell` dismisses and the sign-in surface appears

### Requirement: AppShell with three primary tabs

The signed-in app SHALL present an `AppShell` containing a `TabView` with
exactly three primary tabs in this order: **Library**, **Search**, **Settings**.
**Library** SHALL be the default selected tab on first launch. NowPlaying SHALL
NOT be a tab — it is delivered as the expanded state of the persistent
mini-player (see [[ios-now-playing]]).

#### Scenario: First launch shows Library

- **WHEN** a signed-in user opens the app for the first time
- **THEN** the Library tab is selected and shown

#### Scenario: Tab order is fixed

- **WHEN** the user views the tab bar
- **THEN** the tabs appear in the order Library, Search, Settings, with no
  user-configurable reordering in v1, and there is no NowPlaying tab

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
role tokens and the `Surface` primitive only accepts opaque `Material` tokens
(see [[ios-design-system]]).

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

The first time a track lands in the persistent mini-player on a given device,
the app SHALL display a one-time onboarding hint pointing at the mini-player
with copy explaining the tap-to-open affordance. The hint SHALL dismiss when the
user taps the mini-player, taps the hint's close affordance, or after the sheet
has been expanded once. The hint SHALL NOT reappear on subsequent launches.

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
**ja**, and **zh** (matching the web app's `[[i18n]]` set). The user SHALL be
able to override to a specific language from the Settings tab. The preference
SHALL persist in `UserDefaults`.

#### Scenario: System locale by default

- **WHEN** a Japanese-language device launches the app for the first time
- **THEN** the app's UI strings render in Japanese

#### Scenario: Explicit language override

- **WHEN** the user selects **English** in Settings on a Japanese device
- **THEN** the app immediately re-renders UI strings in English and uses English
  on subsequent launches

### Requirement: Library tab shows the saved-song collection

The Library tab SHALL display the signed-in user's saved songs from `songs`,
ordered most-recently-saved first. Each row SHALL be rendered via the shared
`RowItem` primitive (see [[ios-design-system]]). Tapping a song SHALL call
`NowPlayingState.play(track:)` and SHALL request expansion of the persistent
mini-player into `NowPlayingSheet`. The Library tab SHALL present an empty-state
surface (`EmptyState` primitive) when the user has no saved songs, with copy
directing them to Search or to playing a track in their connected provider.

#### Scenario: Library lists saved songs

- **WHEN** a signed-in user with saved songs opens the Library tab
- **THEN** the list shows their saved songs ordered by save time, most recent
  first, each row rendered with `RowItem` displaying artwork, title, and artist

#### Scenario: Tap expands NowPlayingSheet

- **WHEN** the user taps a song in the Library
- **THEN** `NowPlayingState.play(track:)` is invoked, the lyric fetch begins,
  and the persistent mini-player expands into `NowPlayingSheet` via the shared
  matched-geometry namespace — the active tab does not change

#### Scenario: Empty-state library

- **WHEN** a signed-in user with zero saved songs opens the Library tab
- **THEN** an `EmptyState` card renders with copy explaining how to add songs
  (via Search or by playing a track in the connected provider, then tapping Save
  in NowPlayingSheet)
