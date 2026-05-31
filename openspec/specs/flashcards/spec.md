# flashcards Specification

## Purpose

TBD - created by archiving change add-flashcards. Update Purpose after archive.

## Requirements

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
highlighting. The markers SHALL update when a word is saved or removed, and
SHALL not appear when signed out.

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
cards whose `due_at` is at or before the current time. Each card's front SHALL
show the prompt face determined by the selected study display mode (see "Study
display modes"), and its back SHALL complete the word — kanji, reading, meaning,
and source line — after the learner reveals it. The learner SHALL grade each
revealed card "Again" or "Got it". The schedule SHALL be a `level` (Leitner box
index) and a `due_at` timestamp, ported from the web's schedule: "Got it" SHALL
advance `level` by one (capped at the maximum) and set `due_at` to now plus the
interval for the new level; "Again" SHALL reset `level` to 0 and re-queue the
card in the current session. A grade SHALL be persisted through the same
offline-capable write path as a save. When no cards are due, a "nothing due"
state SHALL be shown.

#### Scenario: Only due cards appear

- **WHEN** a learner enters study mode
- **THEN** only cards with `due_at` at or before now are presented

#### Scenario: Revealing the back

- **WHEN** a learner reveals a card's back
- **THEN** the word is completed — its kanji, reading, meaning, and source line
  are shown, filling in whichever facets the prompt face withheld

#### Scenario: Source line renders as a left-aligned quote block

- **WHEN** a card's source line is shown on the study back-face
- **THEN** it renders as ruby — kanji with their stored readings above — in a
  distinct left-aligned source block with a leading accent rule, and its
  translation aligns to the same left edge, parsed from the saved annotation
  without re-running the tokenizer

#### Scenario: Saved word is highlighted in the source line

- **WHEN** a card's source line is shown on the study back-face
- **THEN** the cells of the saved word (matched on the stored word surface, so a
  kanji run and its okurigana light up together) are tinted with the accent
  while the rest of the line stays dimmed

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

### Requirement: Study display modes

The study screen SHALL offer a selectable display mode that controls only the
prompt face of a card; the reveal SHALL always complete the full word (kanji,
reading, meaning when available, and source line). The available modes form a
recognition ladder, each stripping one reading aid:

- **Glance** — the prompt SHALL show the word's kanji with its reading as
  per-kanji furigana ruby above it (the lyric-surface ruby alignment,
  e.g. いろあ over 色褪 — not the whole reading over the whole word).
- **Read** — the prompt SHALL show the word's kanji with no furigana.
- **Hiragana** — the prompt SHALL show the word's reading in hiragana with no
  kanji.

The selected mode SHALL apply to the whole study session, SHALL be chosen from
the Study screen's display-mode menu (which contains only the modes — no
separate furigana / lyric-line toggles), and SHALL persist across sessions (an
`@AppStorage`-backed preference). The menu's icon SHALL be a display-related
symbol, not the text-size symbol.

#### Scenario: Selecting a mode persists it

- **WHEN** a learner selects a study mode from the Study display-mode menu
- **THEN** every card in the current session uses that prompt face, and the
  selection is restored the next time study mode is entered

#### Scenario: Glance shows per-kanji furigana

- **WHEN** the mode is Glance
- **THEN** the prompt face shows the kanji with each kanji run's reading as
  furigana directly above it (reusing the lyric-surface alignment), and the
  reveal completes the meaning and source line

#### Scenario: Hiragana hides the kanji

- **WHEN** the mode is Hiragana
- **THEN** the prompt face shows only the hiragana reading, and the reveal shows
  the kanji, meaning, and source line

### Requirement: Per-language flashcard glosses

A flashcard's `meaning` and `source_line_translation` SHALL each be stored as a
map keyed by translation-target code, where the keys are exactly the supported
codes `en`, `ja`, and `zh-tw`. The map SHALL be sparse: it contains only the
languages that have been fetched. The shared Supabase columns SHALL be `jsonb`
and both the web and iOS clients SHALL encode and decode this map shape
identically.

#### Scenario: Gloss stored under its language key

- **WHEN** a card's meaning is fetched with the active translation target `en`
- **THEN** the card's meaning map contains key `en` with the English gloss
- **AND** no other language key is added

#### Scenario: Traditional Chinese uses the zh-tw key

- **WHEN** a gloss is fetched while the active language preference is Chinese
  (`zhHant`)
- **THEN** it is stored under the key `zh-tw`
- **AND** not under any other key such as `zhHant` or `zh`

#### Scenario: Existing single-language glosses are dropped on migration

- **WHEN** the schema migration converts the `meaning` and
  `source_line_translation` columns to maps
- **THEN** any previously stored single-language value is discarded and the map
  starts empty
- **AND** the gloss is refetched on demand the next time the card is shown

### Requirement: Glosses are displayed and fetched for the active language

The deck SHALL display the gloss for the learner's currently selected language.
A gloss SHALL be fetched lazily for one language at a time: only when the active
language's key is missing for a field that is needed. Fetching a language SHALL
NOT remove or overwrite glosses already stored for other languages.

#### Scenario: Missing active-language gloss is fetched on demand

- **WHEN** a card has a meaning map without the active language's key
- **AND** the learner requests the meaning
- **THEN** only the active language's gloss is fetched and added to the map

#### Scenario: Switching language refetches only the newly active language

- **WHEN** the learner switches the app language to one whose key is absent from
  a card's gloss map
- **AND** that card is shown
- **THEN** the gloss for the newly active language is fetched
- **AND** glosses previously stored for other languages remain unchanged

#### Scenario: Present gloss is shown without refetching

- **WHEN** a card's gloss map already contains the active language's key
- **THEN** the stored gloss is displayed
- **AND** no translation request is made

### Requirement: Japanese glosses are monolingual definitions

When the active translation target is `ja`, a vocabulary gloss SHALL be a
monolingual Japanese dictionary-style definition rather than a translation, and
the translate request SHALL identify the target language by its name "Japanese".

#### Scenario: Japanese target produces a definition

- **WHEN** a word's meaning is fetched with target `ja`
- **THEN** the request identifies the target language as "Japanese"
- **AND** the returned gloss is a Japanese-language definition of the word

### Requirement: Deck sort options

The iOS deck browse list SHALL let the learner choose the sort order from: date
added, due date, alphabetical by reading, and mastery level. The chosen sort
SHALL persist across launches. The chosen sort SHALL NOT affect study-mode
sequencing, which continues to follow the spaced-repetition schedule.

#### Scenario: Learner changes the deck sort

- **WHEN** the learner selects a sort option other than the default
- **THEN** the deck list reorders by that option
- **AND** the choice is remembered on the next launch

#### Scenario: Sort does not change study order

- **WHEN** the learner changes the deck sort
- **AND** then starts a study session
- **THEN** study mode still presents due cards by the spaced-repetition schedule

### Requirement: Deck filters

The iOS deck browse list SHALL let the learner filter the visible cards by: due
now, by source song, and needs-review (low mastery). Filters SHALL apply on top
of the existing free-text search.

#### Scenario: Filter to cards due now

- **WHEN** the learner applies the "due now" filter
- **THEN** only cards whose schedule is due at the current time are listed

#### Scenario: Filter combines with search

- **WHEN** a filter is active and the learner also types a search query
- **THEN** only cards matching both the filter and the query are listed

### Requirement: Language-aware deck search

Deck search SHALL match a card's surface, its reading, and the gloss stored for
the currently active language.

#### Scenario: Search matches active-language meaning

- **WHEN** the learner searches for text contained in a card's active-language
  gloss
- **THEN** that card appears in the results

#### Scenario: Search ignores other-language glosses

- **WHEN** a card's gloss for a non-active language contains the query but the
  active-language gloss does not
- **THEN** that card is not matched by the gloss; it matches only if its surface
  or reading matches
