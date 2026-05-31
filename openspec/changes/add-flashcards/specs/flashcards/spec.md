## ADDED Requirements

### Requirement: Per-user deck persisted in Supabase with an offline mirror

The app SHALL persist the flashcard deck in the shared `flashcards` Supabase
table, read and written directly through the Supabase Swift client (no Workers
route), with RLS scoping every row to the signed-in user via
`auth.uid() = user_id`. A card's identity SHALL be `(user_id, surface)`, so
saving SHALL be an idempotent upsert keyed on that constraint. The deck SHALL be
mirrored locally in a `FlashcardEntity` SwiftData store inside `OfflineCache`,
the same read-through pattern `songs` and `reading_overrides` use, and the
mirror SHALL be purged on sign-out. The feature SHALL be available only to a
signed-in account.

#### Scenario: Deck is private to the signed-in user

- **WHEN** a signed-in user saves a card
- **THEN** a `flashcards` row is written under their `user_id` and is readable
  only by that user

#### Scenario: Deck restored from the mirror

- **WHEN** the user launches the app while signed in
- **THEN** the deck renders from the local `FlashcardEntity` mirror without
  waiting on the network, and reconciles with the server when online

#### Scenario: Deck cleared on sign-out

- **WHEN** the user signs out
- **THEN** the in-memory deck and the local `FlashcardEntity` mirror are cleared
  so a later session never shows the previous user's cards

### Requirement: Capture a word from the lyric surface

The app SHALL let a signed-in learner save a kanji word (a furigana token's
surface and reading) from the Now Playing lyric surface into the deck. The save
affordance SHALL live in the focus-overlay reading editor opened by
long-pressing a kanji token. A saved card SHALL record the word's surface and
reading and the song context it was captured from — source title, source artist,
and the source lyric line (retained in pipe-annotation form). Saving SHALL be
idempotent per surface, and triggering save for a word already in the deck SHALL
remove it (toggle).

#### Scenario: Saving a new word

- **WHEN** a signed-in learner triggers "Save to flashcards" for a tapped word
  not yet in the deck
- **THEN** a card is created carrying the word's surface, reading, and the
  source song title, artist, and lyric line

#### Scenario: Saving is idempotent

- **WHEN** a learner saves a surface that already exists in the deck
- **THEN** no duplicate card is created

#### Scenario: Re-triggering save removes the word

- **WHEN** a learner triggers the save action for a word already in the deck
- **THEN** the card for that surface is removed from the deck

### Requirement: Saved words are marked on the lyric surface

The lyric surface SHALL mark tokens whose surface is in the deck, using a marker
distinct from the active-line emphasis so it is not confused with playback
highlighting. The markers SHALL update when a word is saved or removed, and SHALL
not appear when signed out.

#### Scenario: A saved word is marked

- **WHEN** a word in the visible lyrics is in the deck
- **THEN** its token shows a saved marker distinct from the active-line emphasis

#### Scenario: Marker clears on removal

- **WHEN** a learner removes a saved word from the deck
- **THEN** its token's saved marker is cleared

### Requirement: Deck view

The app SHALL provide a deck view, reachable from the Study tab, listing every
saved card with its surface, reading, optional meaning, and source song context.
The view SHALL support deleting a card, SHALL filter the list by a text query
matching surface, reading, or meaning, and SHALL show a distinct empty state
when the deck has no cards.

#### Scenario: Listing saved cards

- **WHEN** a learner opens the deck view with a non-empty deck
- **THEN** each saved card is shown with its surface, reading, and source song
  context

#### Scenario: Empty deck

- **WHEN** a learner opens the deck view with no saved cards
- **THEN** an empty state invites them to save words from song lyrics

#### Scenario: Filtering the deck

- **WHEN** a learner types a query into the deck filter
- **THEN** only cards whose surface, reading, or meaning match the query remain
  visible

#### Scenario: Deleting a card

- **WHEN** a learner deletes a card from the deck view
- **THEN** the card is removed from the deck and the list updates

### Requirement: Meaning fetched on demand via the translation route

A card's meaning SHALL be fetched on demand from the existing `/api/translate`
route in glossary mode (`mode: "vocab"`, Japanese → the user's language) when
the card has no stored meaning and the learner reveals or requests it. The
card's source-line translation SHALL be fetched the same way. A fetched value
SHALL be persisted onto the card so it is not re-fetched. A translation failure
(including the per-user quota limit, or being offline) SHALL be non-fatal: the
card SHALL remain usable showing its surface, reading, and source line.

#### Scenario: First reveal fetches a meaning

- **WHEN** a card without a stored meaning is shown or revealed
- **THEN** its meaning is requested from `/api/translate` in vocab mode and
  stored on the card on success

#### Scenario: Translation failure degrades gracefully

- **WHEN** the meaning request fails or the device is offline
- **THEN** the card still renders its surface, reading, and source line, and the
  app does not error

### Requirement: Spaced-repetition study mode

The app SHALL provide a study mode, reachable from the Study tab, that presents
cards whose `due_at` is at or before the current time. Each card SHALL show its
surface on the front and its reading, meaning, and source line on the back after
the learner reveals it. The learner SHALL grade each revealed card "Again" or
"Got it". The schedule SHALL be a `level` (Leitner box index) and a `due_at`
timestamp, ported from the web's schedule: "Got it" SHALL advance `level` by one
(capped at the maximum) and set `due_at` to now plus the interval for the new
level; "Again" SHALL reset `level` to 0 and re-queue the card in the current
session. A grade SHALL be persisted through the same offline-capable write path
as a save. When no cards are due, a "nothing due" state SHALL be shown.

#### Scenario: Only due cards appear

- **WHEN** a learner enters study mode
- **THEN** only cards with `due_at` at or before now are presented

#### Scenario: Revealing the back

- **WHEN** a learner reveals a card's back
- **THEN** the reading, meaning, and source line are shown

#### Scenario: Grading "Got it" advances the schedule

- **WHEN** a learner grades a revealed card "Got it"
- **THEN** the card's `level` increases by one (capped at the maximum) and its
  `due_at` is set to now plus the interval for the new level

#### Scenario: Grading "Again" resets and re-queues

- **WHEN** a learner grades a revealed card "Again"
- **THEN** the card's `level` is reset to 0 and the card is re-queued in the
  current study session

#### Scenario: No cards due

- **WHEN** a learner enters study mode with no cards due
- **THEN** a "nothing due" state is shown instead of a card

### Requirement: Grades and saves survive offline

Saves, removals, and grades SHALL be optimistic local writes mirrored to
`FlashcardEntity` immediately, then pushed to Supabase. While offline or on a
failed push, the write SHALL be queued (a local/pending-delete sync state) and
flushed on the next reconnect; the flush SHALL upload queued writes before
pulling server rows and SHALL reconcile last-writer-wins by `updated_at`, the
same ordering reading-override sync uses.

#### Scenario: Grading offline queues the write

- **WHEN** a learner grades a card while offline
- **THEN** the card's schedule updates locally and the write is queued

#### Scenario: Queued writes flush on reconnect

- **WHEN** the device returns online with queued flashcard writes
- **THEN** the queued upserts and deletes are uploaded, then server rows are
  pulled and reconciled by `updated_at`
