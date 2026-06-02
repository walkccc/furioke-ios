## Purpose

This capability renders furigana for Japanese lyrics entirely on-device by
bundling `kuromoji.umd.js` and its dictionary as resources and running the
tokenizer inside Apple's JavaScriptCore via a Swift bridge. A pure-Swift
line-hash algorithm reproduces the web's `lib/lyrics/line-hash.ts` output
byte-for-byte, and a correction map combines a shared `lib/lyrics/seed.json`
seed with the user's personal overrides to fix readings. An in-memory annotator
turns a raw LRC body plus that correction map into annotated lines, re-running
deterministically whenever the override map changes.

It also lets a listener correct the reading of a kanji word directly on the Now
Playing surface: a long-press on a kanji-bearing token opens a focused reading
editor, and confirming rewrites only that word's reading in the on-screen
rendering. A "Remember this reading" toggle persists the `(surface, reading)`
pair as a personal override so the correction survives future fetches, and the
client reconciles the open document locally so every matching annotation adopts
the new reading immediately. Finally, a Settings-reachable management screen
lists the signed-in user's personal overrides for review, editing, and deletion,
keeping the local cache and Supabase in sync.

## Requirements

### Requirement: Bundled kuromoji.js and dictionary execute inside JavaScriptCore

The iOS app SHALL ship `kuromoji.umd.js` and the kuromoji dictionary files as
bundle resources, and SHALL execute the tokenizer inside Apple's
`JavaScriptCore` framework via a Swift `KuromojiBridge`. The bridge SHALL
override the JS library's default dict-fetch path so dict files load from the
iOS bundle (no network access). The bridge SHALL NOT pull dict files from any
remote URL at any time.

#### Scenario: Tokenizer loads from the bundle

- **WHEN** the app needs to tokenize a lyric line for the first time in a
  session
- **THEN** `JavaScriptCore` evaluates the bundled `kuromoji.umd.js`, resolves
  dict files from the iOS bundle, and produces tokens; no network request is
  issued for tokenizer code or dict files

#### Scenario: No remote dict fetch

- **WHEN** any tokenization call runs
- **THEN** no HTTP request is made for `*.dat`, `*.dat.gz`, or any other
  kuromoji dictionary asset

### Requirement: Tokenizer is module-scope cached for the session

The `KuromojiBridge` SHALL retain its `JSContext` and parsed dictionary at
module scope so the first call's dict-parse cost is paid once per app session.
Subsequent calls SHALL reuse the cached context. On
`applicationDidReceiveMemoryWarning`, the bridge MAY release the `JSContext` and
re-instantiate it on the next call.

#### Scenario: First call pays the dict-load cost

- **WHEN** the first tokenize call of a session runs
- **THEN** the JS context is created, kuromoji.js is evaluated, and the dict is
  loaded (target: under ~700ms on a recent iPhone)

#### Scenario: Subsequent calls are fast

- **WHEN** any tokenize call runs after the first
- **THEN** the cached `JSContext` is reused and tokenization completes in under
  ~5ms per line (no dict reload)

#### Scenario: Memory-warning teardown

- **WHEN** the app receives `applicationDidReceiveMemoryWarning`
- **THEN** the `KuromojiBridge` MAY release its `JSContext` to free ~30–50MB;
  the next tokenize call re-instantiates and pays the first-call cost again

### Requirement: Line-hash algorithm matches the web byte-for-byte

The app SHALL implement the `line_hash` algorithm in pure Swift, matching the
web's `lib/lyrics/line-hash.ts` exactly:

1. Unicode NFKC normalize.
2. Remove all whitespace (replace `/\s+/` with empty string).
3. Strip leading and trailing punctuation characters; preserve internal Japanese
   punctuation (`、`, `。`, `「`, `」`, `（`, `）`, `…`, `―`, etc.).
4. Leave case as-is — no lowercasing.

The hash SHALL be sha256 of the normalized string, hex-encoded, truncated to the
first 32 hex characters (128 bits). Output SHALL be byte-identical to the web
implementation for every possible input.

#### Scenario: Hash byte-equivalence with web

- **WHEN** any lyric line is hashed by both the web's `lib/lyrics/line-hash.ts`
  and the Swift `LineHash` module
- **THEN** the two outputs are byte-identical hex strings

#### Scenario: Internal punctuation participates in the hash

- **WHEN** two lyric lines differ only in an internal Japanese punctuation mark
  (e.g., `、` present vs. absent)
- **THEN** their `line_hash` values differ

#### Scenario: Edge whitespace and punctuation are normalised away

- **WHEN** two lyric lines differ only in trailing whitespace, leading
  punctuation, or interspersed whitespace runs
- **THEN** their `line_hash` values are identical

### Requirement: Built-in seed correction map shared with web

The app SHALL load the same built-in seed correction map the web app uses, from
a shared file at `lib/lyrics/seed.json`, copied into the iOS bundle as a
build-phase artifact. The seed file SHALL be the single source of truth; both
clients SHALL import it without redefining its contents.

#### Scenario: Seed file is shared, not duplicated

- **WHEN** the repository is inspected
- **THEN** `lib/lyrics/seed.json` exists at the repo root and is referenced both
  by the web app's furigana annotator and by the iOS Xcode "Copy Bundle
  Resources" build phase; no second copy of the seed exists in `ios/`

#### Scenario: Seed correction applies without user setup

- **WHEN** any user — signed in or anonymous — opens a song whose lyrics contain
  a seed-mapped surface (e.g., `二人`)
- **THEN** the seed reading is applied during tokenization without user
  configuration

### Requirement: Correction map combines seed and personal overrides

For each annotation pass, the iOS app SHALL build a `CorrectionMap` combining
the bundled seed (entries from `seed.json`) with the user's personal overrides
from `OverrideEntity`. Personal overrides SHALL take precedence over the seed
when a surface appears in both. Phrase matching SHALL be a greedy longest match
over the token sequence: a mapped compound SHALL be corrected whether kuromoji
emits it as one token or splits it.

#### Scenario: Compound is corrected even when kuromoji splits it

- **WHEN** kuromoji tokenizes `二人` as `二` + `人` and the map contains
  `二人 → ふたり`
- **THEN** the phrase-level match still applies and the rendered annotation for
  that compound is `二人` with reading `ふたり`

#### Scenario: Personal override beats the seed

- **WHEN** the user has a personal override for a surface the seed also covers
- **THEN** the personal override's reading is used in the rendered annotation

#### Scenario: Unmapped tokens keep kuromoji's reading

- **WHEN** an annotation pass runs over a kanji token no map entry covers
- **THEN** that token keeps the reading kuromoji produced

### Requirement: Annotator produces annotated lines in memory only

The `FuriganaAnnotator` SHALL accept a raw LRC body and a `CorrectionMap` and
SHALL return an `[AnnotatedLine]` value carrying the surface, reading per kanji
token, and `lineHash` per line. The annotated value SHALL live only in memory
and SHALL NOT be persisted to SwiftData (the raw LRC body is the persisted
form).

#### Scenario: Annotation is in-memory only

- **WHEN** the annotator produces an `[AnnotatedLine]` for a song
- **THEN** the value is held in a SwiftUI view-model property in memory; no
  SwiftData write occurs for tokenized output

#### Scenario: Annotator is deterministic

- **WHEN** the annotator is run twice on the same `(bodyText, CorrectionMap)`
  inputs
- **THEN** the two `[AnnotatedLine]` outputs are equal

### Requirement: Annotator re-runs on override changes

The Now Playing surface SHALL re-run the annotator against the cached raw LRC
body whenever the user's override map changes (an inline editor confirm or a
sync-down from Supabase). The re-run SHALL produce a new `[AnnotatedLine]` value
that the view re-renders against without a `/api/lyrics` round-trip.

#### Scenario: Sync-down rebuilds the correction map

- **WHEN** the override map changes from a sync-down of Supabase
  `reading_overrides`
- **THEN** the `CorrectionMap` is rebuilt with the synced overrides, the
  annotator re-runs over the cached body, and the rendered lyrics reflect the
  new readings, with no `/api/lyrics` call

### Requirement: Long-press a kanji opens the reading editor

The Now Playing surface SHALL open a reading editor when the user long-presses
on a saveable content word in any lyric line. The editor SHALL be presented as a
focus overlay over the lyric surface: the lyric column dims and blurs behind a
dimming scrim, and the editor floats above it as a glass card that echoes the
word's surface and exposes a focused text field pre-filled with the current
reading.

A word the tokenizer splits into several ruby cells (the kanji run plus its
okurigana — 変 + わって, 置 + き + 忘 + れ) SHALL behave as a single interactive
unit: the whole word is one press target and one long-press gesture, keyed on
its shared `wordSurface`. Pressing any cell of the word SHALL give the brief
press-down response (and the light haptic when the long-press fires) across the
_whole_ word, never just the touched cell, and SHALL open the editor for the
whole word. A short tap anywhere on the word SHALL retain its existing
line-tap-to-seek behavior; the long-press gesture SHALL NOT be triggered by
short taps.

Editability follows the word's part of speech, not whether it contains kanji:
saveable content words (名詞・動詞・形容詞・副詞, kanji **or** kana —
e.g. わかって) SHALL be editable, while particles, auxiliaries, and punctuation
SHALL stay inert. The editor SHALL be dismissible via the system keyboard's done
action, an explicit cancel control, or a tap on the dimming scrim outside the
card.

When the learner is signed in, the editor SHALL additionally present a **Save to
flashcards** affordance, in the same lit-glass idiom as its "Remember this
reading" toggle, that reflects whether the word is already in the deck and
toggles its membership. Triggering it SHALL save the word — its surface,
reading, and the song context (source title, source artist, and the source lyric
line) supplied by `NowPlayingState` — into the flashcard deck, or remove it if
already saved. The save affordance SHALL be independent of the
reading-correction action (saving neither requires nor records a correction) and
SHALL NOT appear when signed out.

#### Scenario: Long-press opens the editor

- **WHEN** the user long-presses on a saveable word in a rendered line
- **THEN** the lyric column dims and a glass editor card appears, echoing the
  word's surface with a focused field pre-filled with the current hiragana
  reading

#### Scenario: A multi-cell word presses as one unit

- **WHEN** the user presses any cell of a word the tokenizer split across cells
  (the 変 or the わって of 変わって)
- **THEN** the entire word gives the press-down response together, and the
  long-press opens the editor for the whole word's surface and reading — not the
  single touched cell

#### Scenario: A kana content word is editable

- **WHEN** the user long-presses a saveable kana word (e.g. わかって) carrying
  no kanji
- **THEN** the reading editor opens for that word

#### Scenario: Short tap still seeks

- **WHEN** the user short-taps a kanji on a playable surface
- **THEN** the line-tap seek runs and the inline reading editor does NOT open

#### Scenario: Outside tap dismisses without saving

- **WHEN** the editor is open and the user taps the dimming scrim outside the
  card
- **THEN** the editor closes, no override is recorded, and the lyrics are
  unchanged

#### Scenario: Saving a word to the deck from the editor

- **WHEN** a signed-in user triggers "Save to flashcards" in the editor for a
  word not yet in the deck
- **THEN** the word is saved to the deck with its surface, reading, and the
  current song's title, artist, and source line, and the affordance reflects the
  saved state

#### Scenario: Save affordance hidden when signed out

- **WHEN** a signed-out user opens the reading editor
- **THEN** no save-to-flashcards affordance is shown

### Requirement: Confirm rewrites the edited word

Confirming the editor SHALL replace only the edited word's reading in the
on-screen rendering; no other annotation SHALL be touched. The new reading SHALL
be applied immediately via local reconciliation (no `/api/lyrics` round-trip).

#### Scenario: Confirm updates one annotation

- **WHEN** the user changes the reading and confirms
- **THEN** that word's rendered reading becomes the new reading; no other
  annotation is touched

#### Scenario: Empty reading cannot be confirmed

- **WHEN** the reading text field is empty
- **THEN** the confirm action is disabled

### Requirement: "Remember this reading" toggle persists an override

The reading editor SHALL present a personal-override toggle, labeled **Remember
this reading** in the UI, defaulting to enabled. When enabled and the user
confirms, the `(surface, reading)` pair SHALL be persisted as a personal
override via the existing backend (writing to `reading_overrides`), AND the
local `OverrideEntity` SHALL be updated immediately. When disabled, confirming
SHALL change only the current rendering without persisting.

#### Scenario: Toggle enabled persists an override

- **WHEN** the user enables **Remember this reading**, edits the reading, and
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

- **WHEN** the user enables **Remember this reading** and confirms while offline
- **THEN** the local `OverrideEntity` is written with `source = local`, the
  rendering updates immediately, and the upload is queued for the next online
  tick

### Requirement: Reading edit reconciles other matching annotations

The client SHALL reconcile the currently displayed lyrics locally whenever an
override is persisted (via **Remember this reading**) so every annotation in the
open document whose surface matches the edited override is rewritten to the new
reading immediately, without a `/api/lyrics` round-trip.

#### Scenario: Override propagates across the open document

- **WHEN** the user records an override for `二人 → ふたり` via the inline
  editor with **Remember this reading** enabled
- **THEN** every annotation in the currently rendered lyrics whose surface is
  `二人` is rewritten to use the reading `ふたり` within one render frame, with
  no `/api/lyrics` round-trip

### Requirement: Reading overrides management screen

The app SHALL provide a screen, reachable from Settings, that lists the
signed-in user's reading overrides for review and cleanup. The list SHALL show
only the user's own overrides, not the bundled seed corrections.

#### Scenario: Viewing the user's overrides

- WHEN a signed-in user opens the Reading Overrides screen
- THEN each of their overrides is shown as `kanji → reading`
- AND each row shows whether it is synced to the server or pending sync
- AND overrides marked for deletion are not shown

#### Scenario: Empty state

- WHEN a signed-in user with no overrides opens the screen
- THEN an empty-state message is shown instead of a list

#### Scenario: Searching the list

- WHEN the user types into the search field
- THEN the list is filtered to overrides whose kanji or reading match the query

#### Scenario: Not signed in

- WHEN a signed-out user reaches the screen
- THEN a sign-in prompt is shown instead of the list (overrides are per-user)

### Requirement: Editing an override reading

The screen SHALL let the user change the reading of an existing override,
reusing the same reading editor used during playback.

#### Scenario: Edit a reading

- WHEN the user edits an override's reading and saves a non-empty value
- THEN the override is updated in the local cache
- AND the change is synced to Supabase
- AND the new reading takes effect the next time a song containing that kanji
  loads

### Requirement: Deleting an override

The screen SHALL let the user delete an override, and the deletion SHALL
propagate to Supabase so other clients (e.g. the web app) reflect the removal.

#### Scenario: Delete while online

- WHEN the user deletes an override while online
- THEN the override is removed from Supabase
- AND it is removed from the local cache and the list

#### Scenario: Delete while offline

- WHEN the user deletes an override while offline
- THEN the override is marked for deletion locally and disappears from the list
- AND it is NOT silently dropped from the cache
- AND on the next reconnect the pending deletion is sent to Supabase as a DELETE

#### Scenario: Deferred re-annotation

- WHEN an override is edited or deleted from this screen while a song is playing
- THEN the currently displayed lyrics are not forced to re-render
- AND the change takes effect the next time lyrics are loaded
