## ADDED Requirements

### Requirement: Long-press a kanji opens the inline reading editor

The Now Playing surface SHALL open an inline reading editor anchored near the
targeted word when the user long-presses on a kanji-bearing token in any lyric
line. The editor SHALL display the kanji surface and a focused text field
pre-filled with the current reading. A short tap on a kanji SHALL retain its
existing line-tap-to-seek behavior (see [[ios-now-playing]]); the long-press
gesture SHALL NOT be triggered by short taps. The editor SHALL be dismissible
via the system keyboard's done action, an explicit cancel control, or a tap
outside.

#### Scenario: Long-press opens the editor

- **WHEN** the user long-presses on a kanji word in a rendered line
- **THEN** an inline reading editor appears with the kanji surface shown and a
  focused field pre-filled with the current hiragana reading

#### Scenario: Short tap still seeks

- **WHEN** the user short-taps a kanji on a playable surface
- **THEN** the line-tap seek runs (per [[ios-now-playing]]) and the inline
  reading editor does NOT open

#### Scenario: Outside tap dismisses without saving

- **WHEN** the editor is open and the user taps outside it
- **THEN** the editor closes, no override is recorded, and the lyrics are
  unchanged

### Requirement: Confirm rewrites the edited word

Confirming the editor SHALL replace only the edited word's reading in the
on-screen rendering; no other annotation SHALL be touched. The new reading SHALL
be applied immediately via local reconciliation (no `/api/lyrics` round-trip),
matching the seam defined in the `[[furigana]]` "Reconcile existing annotations
against the map" requirement.

#### Scenario: Confirm updates one annotation

- **WHEN** the user changes the reading and confirms
- **THEN** that word's rendered reading becomes the new reading; no other
  annotation is touched

#### Scenario: Empty reading cannot be confirmed

- **WHEN** the reading text field is empty
- **THEN** the confirm action is disabled

### Requirement: "Apply to all songs" toggle persists an override

The inline reading editor SHALL present an **Apply to all songs** toggle. When
enabled and the user confirms, the `(surface, reading)` pair SHALL be persisted
as a personal override via the existing backend (writing to
`furigana_overrides`), AND the local `OverrideEntity` SHALL be updated
immediately (see [[ios-offline-cache]]). When disabled, confirming SHALL change
only the current rendering without persisting.

#### Scenario: Toggle enabled persists an override

- **WHEN** the user enables **Apply to all songs**, edits the reading, and
  confirms while online
- **THEN** the local `OverrideEntity` is written with `source = local`, an
  upload is dispatched to the backend, and on success the row becomes
  `source = synced`

#### Scenario: Toggle disabled is local-and-temporary

- **WHEN** the user leaves the toggle disabled and confirms
- **THEN** the current rendering reflects the new reading for the remainder of
  the session; no override row is written; the next `/api/lyrics` fetch reverts
  to the seed or kuromoji reading

#### Scenario: Offline override queues for upload

- **WHEN** the user enables **Apply to all songs** and confirms while offline
- **THEN** the local `OverrideEntity` is written with `source = local`, the
  rendering updates immediately, and the upload is queued for the next online
  tick (see [[ios-offline-cache]])

### Requirement: Reading edit reconciles other matching annotations

The client SHALL reconcile the currently displayed lyrics locally whenever an
override is persisted (via **Apply to all songs**) so every annotation in the
open document whose surface matches the edited override is rewritten to the new
reading immediately, without a `/api/lyrics` round-trip. This SHALL mirror the
`[[furigana]]` "Reconcile existing annotations against the map" behavior.

#### Scenario: Override propagates across the open document

- **WHEN** the user records an override for `二人 → ふたり` via the inline
  editor with **Apply to all songs** enabled
- **THEN** every annotation in the currently rendered lyrics whose surface is
  `二人` is rewritten to use the reading `ふたり` within one render frame, with
  no `/api/lyrics` round-trip
