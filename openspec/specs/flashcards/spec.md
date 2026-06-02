# flashcards Specification

## Purpose

TBD - created by archiving change add-flashcards. Update Purpose after archive.

## Requirements

### Requirement: Flashcards require a permanent account

The flashcard feature SHALL be reserved for a permanent (non-anonymous) account
— saving a word from the lyric surface, the Study-tab deck view, study mode, and
the saved-word markers on lyrics. A guest (anonymous) session SHALL NOT be able
to save cards, and saved-word markers SHALL NOT appear for a guest. When a guest
triggers a flashcard save or opens the deck/study surfaces, the app SHALL
present the shared in-app sign-in prompt (Apple and Google) instead of
performing the action, and the feature SHALL become available only once the
guest upgrades to a permanent account. This gate is the contract the (separately
built) flashcards UI plugs into; it does not by itself build the feature.

#### Scenario: Guest triggering a flashcard save is prompted to sign in

- **WHEN** a guest (anonymous) session triggers "Save to flashcards" for a word
- **THEN** the in-app sign-in prompt is presented, no card is created, and the
  save proceeds only after the guest upgrades to a permanent account

#### Scenario: Saved-word markers do not appear for a guest

- **WHEN** a guest views lyrics
- **THEN** no saved-word markers are shown, since a guest has no deck

#### Scenario: Deck and study are available after upgrade

- **WHEN** a guest upgrades to a permanent account
- **THEN** the deck view, study mode, and word-capture become available under
  their `user_id`

### Requirement: Per-user deck persisted in Supabase with an offline mirror

The app SHALL persist the flashcard deck in the shared `flashcards` Supabase
table, read and written directly through the Supabase Swift client (no Workers
route), with RLS scoping every row to the account user via
`auth.uid() = user_id`. A card's identity SHALL be `(user_id, surface)`, so
saving SHALL be an idempotent upsert keyed on that constraint. The deck SHALL be
mirrored locally in a `FlashcardEntity` SwiftData store inside `OfflineCache`,
the same read-through pattern `songs` and `reading_overrides` use, and the
mirror SHALL be purged on sign-out. The feature SHALL be available only to a
permanent (non-anonymous) account; a guest (anonymous) session SHALL NOT persist
a deck and SHALL be prompted to sign in instead.

#### Scenario: Deck is private to the account user

- **WHEN** a permanent-account user saves a card
- **THEN** a `flashcards` row is written under their `user_id` and is readable
  only by that user

#### Scenario: Deck restored from the mirror

- **WHEN** a permanent-account user launches the app
- **THEN** the deck renders from the local `FlashcardEntity` mirror without
  waiting on the network, and reconciles with the server when online

#### Scenario: Deck cleared on sign-out

- **WHEN** the user signs out
- **THEN** the in-memory deck and the local `FlashcardEntity` mirror are cleared
  so a later session never shows the previous user's cards

#### Scenario: Guest has no deck

- **WHEN** a guest (anonymous) session is active
- **THEN** no deck is loaded or persisted, and attempting to save prompts the
  guest to sign in

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

The app SHALL provide a deck view, reachable as a **"browse" destination from
the 単語 tab's swipe deck**, listing every saved card with its surface, reading,
optional meaning, and source song context. The view SHALL support deleting a
card, SHALL filter the list by a text query matching surface, reading, or
meaning, and SHALL show a distinct empty state when the deck has no cards.

#### Scenario: Reaching the deck list from the swipe deck

- **WHEN** a learner taps the browse affordance on the 単語 tab's swipe deck
- **THEN** the deck list of every saved card is shown

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

The app SHALL provide a study mode as the **root of the 単語 tab**, presenting
cards whose `due_at` is at or before the current time as a swipeable card stack.
The top card's front SHALL show the prompt face determined by the selected study
display mode (see "Study display modes"). Tapping the card SHALL flip it between
its front and its back with a 3D flip animation; the back SHALL complete the
word, rendering the word itself as **furigana ruby** — its reading set above the
kanji, using the same ruby rendering the lyric surface uses, never a
parenthesized `surface（reading）` — together with its meaning and the source
line. A card SHALL be swipeable from either face (the learner is not required to
reveal the back first).

The learner SHALL grade the top card by swiping it: **swiping left grades
"Again"** and **swiping right grades "Got it"**. A horizontal drag SHALL tilt
and translate the card and SHALL surface a directional affordance — a "Forget"
indicator toward the left and a "Remember" indicator toward the right — whose
prominence increases with drag distance. Releasing past a distance threshold
SHALL commit the grade and animate the card off-screen, after which the next due
card SHALL surface; releasing before the threshold SHALL spring the card back
with no grade. Tap-to-flip and drag-to-grade SHALL be disambiguated so a drag
never triggers a flip.

The schedule SHALL be a `level` (Leitner box index) and a `due_at` timestamp,
ported from the web's schedule: "Got it" SHALL advance `level` by one (capped at
the maximum) and set `due_at` to now plus the interval for the new level;
"Again" SHALL reset `level` to 0 and re-queue the card in the current session. A
grade SHALL be persisted through the same offline-capable write path as a save.
When no cards are due, a "nothing due" state SHALL be shown. The cards SHALL be
rendered as iOS 26 Liquid Glass surfaces over the artwork backdrop.

#### Scenario: Study is the tab root

- **WHEN** the learner selects the 単語 tab
- **THEN** the swipeable card stack of due cards is shown as the tab's root, not
  a deck list

#### Scenario: Only due cards appear

- **WHEN** a learner enters study mode
- **THEN** only cards with `due_at` at or before now are presented

#### Scenario: Tapping flips the card

- **WHEN** the learner taps the top card showing its front
- **THEN** the card flips with a 3D flip to its back, completing the word — the
  word as furigana ruby (reading above the kanji), its meaning, and the source
  line — filling in whichever facets the prompt face withheld
- **AND** tapping again flips it back to the front

#### Scenario: Back-face word renders as furigana ruby

- **WHEN** the back face of a card is shown
- **THEN** the word renders as ruby — its reading set above the kanji, the same
  rendering the lyric surface uses — and never as a parenthesized
  `surface（reading）` form

#### Scenario: Dragging surfaces a directional grade affordance

- **WHEN** the learner drags the top card horizontally
- **THEN** the card tilts and translates with the drag, and a "Forget" indicator
  (toward the left) or a "Remember" indicator (toward the right) grows more
  prominent as the drag distance increases

#### Scenario: Releasing before the threshold cancels

- **WHEN** the learner releases a dragged card before crossing the distance
  threshold
- **THEN** the card springs back to center and no grade is recorded

#### Scenario: Swiping right grades "Got it" and advances the schedule

- **WHEN** the learner swipes the top card right past the threshold
- **THEN** the card animates off-screen, its `level` increases by one (capped at
  the maximum), its `due_at` is set to now plus the interval for the new level,
  and the next due card surfaces

#### Scenario: Swiping left grades "Again" and re-queues

- **WHEN** the learner swipes the top card left past the threshold
- **THEN** the card animates off-screen, its `level` is reset to 0, and the card
  is re-queued at the back of the current study session

#### Scenario: A card can be graded from either face

- **WHEN** the top card is showing its back
- **THEN** the learner can still swipe it left or right to grade it without
  flipping back to the front first

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

One further mode tests recall in song context:

- **Cloze ("In context")** — the prompt SHALL show the card's captured source
  lyric line rendered as ruby, with the cells of the saved word (matched on the
  stored surface, so a kanji run and its okurigana blank together) replaced by a
  blank, so the learner recalls the word inside the sentence they heard it sung
  in. A card with no source line, or whose surface cannot be located in the
  source line, SHALL fall back to the Glance prompt for that card.

The selected mode SHALL apply to the whole study session, SHALL be chosen from a
display-mode menu on the swipe-deck root (which contains only the modes — no
separate furigana / lyric-line toggles), and SHALL persist across sessions (an
`@AppStorage`-backed preference). The menu's icon SHALL be a display-related
symbol, not the text-size symbol.

#### Scenario: Selecting a mode persists it

- **WHEN** a learner selects a study mode from the display-mode menu on the
  swipe deck
- **THEN** every card in the current session uses that prompt face, and the
  selection is restored the next time the 単語 tab is entered

#### Scenario: Glance shows per-kanji furigana

- **WHEN** the mode is Glance
- **THEN** the prompt face shows the kanji with each kanji run's reading as
  furigana directly above it (reusing the lyric-surface alignment), and the
  flipped back completes the meaning and source line

#### Scenario: Hiragana hides the kanji

- **WHEN** the mode is Hiragana
- **THEN** the prompt face shows only the hiragana reading, and the flipped back
  shows the kanji, meaning, and source line

#### Scenario: Cloze blanks the word inside its source line

- **WHEN** the mode is Cloze and the card has a source line containing the saved
  word
- **THEN** the prompt face shows the source line as ruby with the saved word's
  cells replaced by a blank, and the flipped back completes the word, meaning,
  and source line as usual

#### Scenario: Cloze falls back when there is no usable source line

- **WHEN** the mode is Cloze and the card has no source line, or its surface
  cannot be located within the source line
- **THEN** that card's prompt falls back to the Glance face

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

### Requirement: Captured source-line timestamp

The app SHALL record, when a word is saved from the lyric surface and the open
song has synced (timestamped) lyrics, the captured source line's start time and
its end time (the next timed line's start) on the card as millisecond offsets,
alongside the existing source title, artist, and line. The end lets study bound
playback to just that line without the song's lyrics being loaded. The
timestamps SHALL be persisted on the card through the same offline-capable write
path as the rest of the save, stored in new nullable `source_line_start_ms` /
`source_line_end_ms` columns on the shared `flashcards` table and the local
`FlashcardEntity` mirror, and SHALL round-trip and sync across devices like any
other card field. The end SHALL be empty for the last timed line. When the song
has no synced lyrics, or the line's start time cannot be resolved, the card
SHALL be saved with no timestamp, and this SHALL be non-fatal — the save and
every other card behavior SHALL proceed unchanged. The timestamp is captured
once at save time and SHALL NOT be re-resolved later, so it remains valid even
if the song's lyric match changes.

When a track is playing at save time, the app SHALL also record that track's
provider and provider track id on the card (nullable `source_provider` /
`source_track_id` columns and `FlashcardEntity` fields), captured once,
persisted and synced through the same path, so study can later start that exact
song. When nothing is playing, these SHALL be left empty and the save SHALL
proceed normally.

#### Scenario: Saving while a song plays records the source track reference

- **WHEN** a learner saves a word while a track is playing
- **THEN** the card records that track's provider and provider track id
- **AND** the values are persisted and synced like the rest of the card

#### Scenario: Saving from a synced song records the line timestamp

- **WHEN** a learner saves a word from a song that has synced lyrics
- **THEN** the card records the start-time offset (in milliseconds) of the
  source line it was captured from
- **AND** the value is persisted and synced like the rest of the card

#### Scenario: Saving from an unsynced song records no timestamp

- **WHEN** a learner saves a word from a song with no synced lyrics, or whose
  source line has no resolvable start time
- **THEN** the card is saved with no source-line timestamp
- **AND** the save and all other card behavior proceed normally

#### Scenario: Existing cards have no timestamp

- **WHEN** a card was saved before this field existed (its
  `source_line_start_ms` is absent)
- **THEN** the card renders and studies normally, treated as having no timestamp

### Requirement: Play the source line in study

The study screen SHALL place a play affordance at the start of the captured
source line wherever that line is rendered — the back face's quote block and the
Cloze prompt — and the affordance SHALL always be present there, not gated on
playback state. On activation it SHALL play **just that line** — seek to the
line's start time and pause at its end (the captured next-line time, falling
back to the active track's loaded lyrics for an older card; no pause when there
is no known end). It SHALL NOT play the song from its start, and SHALL NOT
present the Now Playing surface.

- When the card's source song is already the active track, it SHALL seek and
  play the line directly.
- Otherwise, when the card carries a source track reference whose provider is
  the active music provider, it SHALL first start that song headlessly —
  connecting to the provider if needed, without presenting Now Playing — and
  then play the line.
- When the card has no captured start time, or no track reference and its song
  is not active, or the reference's provider is not the active provider
  (providers cannot be switched automatically), activating SHALL be inert — it
  SHALL NOT seek an unrelated song.

The pause SHALL fire only while that same track is still current, so a song the
learner started in the meantime is not interrupted. Activating the affordance
SHALL NOT advance, flip, or grade the card.

#### Scenario: The play affordance sits at the start of the source line

- **WHEN** a card's source line is shown (the back face, or the Cloze prompt)
- **THEN** a play affordance is shown at the start of that line, regardless of
  whether the source song is currently playing

#### Scenario: Activating plays only that line when the source song is active

- **WHEN** the card has a source-line start time, its source song is the active
  track, and the learner activates the play affordance
- **THEN** the song seeks to that line's start time, plays, and pauses at the
  line's end — without presenting Now Playing

#### Scenario: Activating starts the source song headlessly when it isn't playing

- **WHEN** the card carries a source track reference whose provider is the
  active provider, that song is not the active track, and the learner activates
  the affordance
- **THEN** the source song starts (connecting to the provider if needed) without
  presenting Now Playing, then seeks to the line and pauses at its end — it does
  not play from the song's start

#### Scenario: Activating is inert when the line can't be played

- **WHEN** the card has no captured start time, or no track reference and its
  song is not active, or the reference's provider is not the active provider
- **THEN** activating the affordance does nothing — no unrelated song is seeked
  or started

#### Scenario: Playing does not grade the card

- **WHEN** the learner activates the play affordance
- **THEN** playback starts and the card is neither flipped, advanced, nor graded

### Requirement: Study feedback and session completion

The study screen SHALL give the learner sensory and visual feedback during a
session. Flipping a card and committing a grade SHALL each produce haptic
feedback. Consecutive "Got it" grades within a session SHALL be tracked as a
combo and surfaced to the learner, and the combo SHALL reset when a card is
graded "Again". When a "Got it" grade promotes a card to a higher Leitner box,
the screen SHALL show a brief level-up cue. When the learner finishes every card
seeded into the session, the screen SHALL show a session-complete celebration
(in place of, or distinct from, the "nothing due" state that is shown when no
cards were due to begin with). None of this feedback SHALL change the
spaced-repetition schedule or what counts as a grade. Feedback state is
session-local and SHALL NOT be persisted.

#### Scenario: Grading produces haptic feedback

- **WHEN** the learner flips a card or commits a grade by swiping past the
  threshold
- **THEN** the device produces haptic feedback for that action

#### Scenario: A run of correct grades builds a combo

- **WHEN** the learner grades several cards "Got it" in a row within one session
- **THEN** a combo count is surfaced and increases with each consecutive "Got
  it"
- **AND** grading a card "Again" resets the combo

#### Scenario: A promotion shows a level-up cue

- **WHEN** a "Got it" grade advances a card to a higher Leitner box
- **THEN** a brief level-up cue is shown

#### Scenario: Finishing the session shows a celebration

- **WHEN** the learner grades the last card seeded into the study session
- **THEN** a session-complete celebration is shown rather than the silent
  caught-up state

#### Scenario: Entering with nothing due is not a celebration

- **WHEN** the learner enters study mode with no cards due
- **THEN** the "nothing due" state is shown, not the session-complete
  celebration
