## Purpose

Defines Furioke's first-launch onboarding flow: a one-time, skippable tutorial
presented over the `AppShell` that welcomes the user, lets them set their
interface language, walks them through best-effort setup (music provider and
native language) using the same controls as Settings, and teaches the core
workflow through illustrated cards. The flow is gated by a persisted
`hasCompletedOnboarding` flag, works for both guest and permanent sessions, and
can be replayed from Settings.

### Requirement: First-launch onboarding gate and one-time completion

The app SHALL present the onboarding flow exactly once on the first launch on a
given device, gated by a persisted `hasCompletedOnboarding` flag on
`PreferencesState` stored in `UserDefaults` and written through on set. The flag
SHALL default to `false` when absent. Both completing the flow ("Got it") and
skipping it ("Skip for now" / the per-screen "Skip") SHALL set the flag to
`true`. While the flag is `false`, the flow SHALL be presented over the
`AppShell`; while it is `true`, the flow SHALL NOT be presented. The flow SHALL
be presented for both guest (anonymous) and permanent sessions and SHALL NOT
require a session to proceed.

#### Scenario: First launch presents onboarding

- **WHEN** the app launches and `hasCompletedOnboarding` is `false`
- **THEN** the onboarding flow is presented over the `AppShell`, starting on the
  welcome screen

#### Scenario: Completion persists and does not return

- **WHEN** the user finishes the flow with "Got it" (or skips it) and later
  relaunches the app
- **THEN** `hasCompletedOnboarding` is `true`, persisted in `UserDefaults`, and
  the onboarding flow is not presented again

#### Scenario: Guest is not forced to sign in

- **WHEN** a guest (anonymous) session reaches any point in the onboarding flow
- **THEN** the flow proceeds without requiring sign-in and, on completion or
  skip, lands the user in the `AppShell` as a guest

### Requirement: Welcome screen

The onboarding flow SHALL open with a welcome screen that communicates the app's
core value. It SHALL present the title "Welcome to Furioke", a value proposition
describing singing along with Japanese songs, understanding the lyrics, and
saving words to learn, and the pain point that Japanese lyrics are hard without
strong kanji knowledge and that Furioke helps with furigana, translations, and
word-level tools. The bottom bar SHALL present a single prominent primary
call-to-action that starts the tutorial ("Start your Furioke journey" / "Start
tutorial") and, beneath it, exactly one quiet, non-blocking sign-in affordance
labeled "Already have an account? Log in" that opens the existing in-app sign-in
prompt without leaving or dismissing the onboarding flow. The escape-hatch
"Skip" action SHALL NOT appear in the bottom bar; it SHALL live in the
top-trailing corner of the welcome chrome (the same corner it occupies on every
tutorial step), and tapping it SHALL complete onboarding immediately.

#### Scenario: Welcome content is shown

- **WHEN** the welcome screen appears
- **THEN** it shows the "Welcome to Furioke" title, the value proposition, the
  kanji-difficulty pain point, a single prominent "Start tutorial" CTA with one
  quiet "Already have an account? Log in" link beneath it, and a "Skip" action
  in the top-trailing corner (not in the bottom bar)

#### Scenario: Start advances to the tutorial

- **WHEN** the user taps the primary "Start tutorial" CTA
- **THEN** the flow advances to the first setup step

#### Scenario: Skip completes onboarding

- **WHEN** the user taps "Skip" in the top-trailing corner of the welcome screen
- **THEN** the flow sets `hasCompletedOnboarding` to `true`, dismisses, and the
  user lands in the `AppShell` on the Library tab

#### Scenario: Log in is optional and non-blocking

- **WHEN** the user taps "Already have an account? Log in"
- **THEN** the existing in-app sign-in prompt is presented over the flow, and
  dismissing or completing it returns the user to the same point in the
  onboarding flow rather than ending it

### Requirement: Choose interface language upfront

The welcome screen SHALL offer an app-language picker over `LanguagePreference`
(English, 日本語, 中文) so the user can set the interface language before
starting the tutorial. Changing it SHALL update `PreferencesState.language`
(persisted as before) and SHALL re-render the in-progress onboarding flow in the
chosen language, so the tutorial copy appears in the user's own language. The
picker SHALL be presented as a compact globe icon in the top-leading corner of
the welcome chrome (leaving the top-trailing corner for Skip) and SHALL be
reachable from the welcome screen without leaving it.

#### Scenario: Welcome offers a language picker

- **WHEN** the welcome screen appears
- **THEN** a compact globe-icon app-language picker offering English, 日本語,
  and 中文 is available in the top-leading corner of the welcome chrome

#### Scenario: Switching language re-renders the flow live

- **WHEN** the user selects 日本語 from the welcome language picker
- **THEN** `PreferencesState.language` becomes `.ja`, the choice is persisted,
  and the onboarding copy re-renders in Japanese without dismissing the flow

### Requirement: Inline setup steps reuse existing controls

The tutorial SHALL present two setup steps inline before the teaching cards.
Step 1 SHALL let the user choose a music provider using the same provider
selector control as the Settings tab; connecting the chosen provider SHALL be
best-effort and skippable, and the step SHALL NOT block on a successful
connection (including when connecting bounces out to an external provider app
for authorization). Step 2 SHALL let the user choose a native language from
`NativeLanguagePreference` (English and 中文), updating
`PreferencesState.nativeLanguage`, and SHALL explain that this language is used
for lyric translations and word meanings. Both setup steps SHALL be skippable
and SHALL preserve any selection the user makes.

#### Scenario: Provider step reuses the Settings selector

- **WHEN** the provider setup step appears
- **THEN** it presents the same provider selector used in Settings, listing
  `MusicState.availableProviders`, with copy explaining that choosing a provider
  lets Furioke play along with songs the user already listens to

#### Scenario: Provider connect is best-effort

- **WHEN** the user taps a provider whose connect bounces out to an external app
  or fails
- **THEN** the onboarding flow does not block — the persisted onboarding state
  lets the user resume the flow on return, and a failed connect leaves the flow
  advanceable

#### Scenario: Native language selection persists

- **WHEN** the user chooses 中文 in the native-language step
- **THEN** `PreferencesState.nativeLanguage` becomes the Chinese case and is
  persisted, and the step explains it drives translations and word meanings

#### Scenario: Setup steps are skippable

- **WHEN** the user advances past a setup step without making a selection
- **THEN** the flow proceeds and the corresponding preference keeps its prior /
  default value

### Requirement: Illustrated teaching cards

The tutorial SHALL present the remaining workflow as a sequence of illustrated
teaching cards that describe the app rather than driving the live UI. Each card
SHALL pair short, calm copy with a simple visual sketch (e.g. SF Symbols) and
SHALL NOT require live app state (network, sign-in, an active provider, or
playback) to be shown. The cards SHALL cover, in order: searching for a Japanese
song, adding a song to the library, playing along with synced lyrics, toggling
the furigana / rōmaji / translation helpers from the top-right toolbar,
long-pressing a word to save it to the Tango List or override its
reading/meaning, and the Tango List itself with its list and flashcard study
modes. The cards' copy SHALL track the app's real four-tab navigation and
feature names.

#### Scenario: Teaching cards cover the full workflow

- **WHEN** the user advances through the teaching cards
- **THEN** they encounter, in order, cards for Search, Add to Library, Play
  along with synced lyrics, Toggle helpers (furigana / rōmaji / translation),
  Long-press a word (save or override), and the Tango List (list and flashcard
  study modes)

#### Scenario: Teaching cards never dead-end

- **WHEN** the device has no network, no connected provider, and no active
  playback
- **THEN** every teaching card still renders its copy and sketch, and the user
  can advance through all of them and finish the flow

#### Scenario: Finishing completes onboarding

- **WHEN** the user reaches the final teaching card and taps "Got it"
- **THEN** the flow sets `hasCompletedOnboarding` to `true`, dismisses, and the
  user lands in the `AppShell` on the Library tab

### Requirement: Replay onboarding from Settings

The user SHALL be able to re-present the onboarding flow after completing it,
via a "Replay Tutorial" action in the Settings Customization section. Triggering
it SHALL clear `PreferencesState.hasCompletedOnboarding`, which re-presents the
onboarding cover over the shell, starting again from the welcome screen.
Completing or skipping the replayed flow SHALL set the flag again as on first
launch.

#### Scenario: Replay re-presents the flow

- **WHEN** a user who has completed onboarding taps "Replay Tutorial" in
  Settings
- **THEN** `hasCompletedOnboarding` is cleared and the onboarding flow is
  presented again from the welcome screen

#### Scenario: Replayed flow completes like first launch

- **WHEN** the user finishes or skips the replayed flow
- **THEN** `hasCompletedOnboarding` is set to `true` again and the flow does not
  reappear until replayed once more

### Requirement: Navigation, progress, and skip affordances

The tutorial SHALL be a paged sequence the user advances through, with a visible
progress indication of position within the flow and a persistent skip affordance
available from every step that completes onboarding immediately. Page
transitions SHALL use the existing `Motion` tokens rather than ad-hoc
animations, and the flow SHALL honor the design system's Reduce Transparency and
Dynamic Type guarantees.

#### Scenario: Progress is shown across steps

- **WHEN** the user is on any tutorial step
- **THEN** a progress indication shows the user's position within the sequence

#### Scenario: Skip is always available

- **WHEN** the user taps the skip affordance on any step
- **THEN** the flow sets `hasCompletedOnboarding` to `true` and dismisses to the
  `AppShell`

#### Scenario: Accessible by construction

- **WHEN** the flow is viewed under Reduce Transparency or with a large Dynamic
  Type size
- **THEN** glass surfaces fall back to opaque material and the copy scales and
  remains legible, consistent with the rest of the app
