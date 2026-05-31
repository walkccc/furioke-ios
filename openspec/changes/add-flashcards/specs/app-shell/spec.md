## MODIFIED Requirements

### Requirement: AppShell with three primary tabs

The signed-in app SHALL present an `AppShell` containing a `TabView` with
exactly four primary tabs in this order: **Library**, **Search**, **Study**,
**Settings**. **Library** SHALL be the default selected tab on first launch. The
**Study** tab SHALL host the flashcard deck and study mode as a
`NavigationStack`. NowPlaying SHALL NOT be a tab — it is delivered as the
expanded state of the persistent mini-player.

#### Scenario: First launch shows Library

- **WHEN** a signed-in user opens the app for the first time
- **THEN** the Library tab is selected and shown

#### Scenario: Tab order is fixed

- **WHEN** the user views the tab bar
- **THEN** the tabs appear in the order Library, Search, Study, Settings, with no
  user-configurable reordering in v1, and there is no NowPlaying tab

#### Scenario: Study tab hosts the flashcard deck

- **WHEN** the user selects the Study tab
- **THEN** the flashcard deck view is shown, from which study mode can be entered

#### Scenario: Per-tab scroll state survives switching

- **WHEN** the user scrolls partway through the Library tab, switches to Search,
  and switches back
- **THEN** the Library tab returns to the same scroll position; tab state is not
  reset on switch
