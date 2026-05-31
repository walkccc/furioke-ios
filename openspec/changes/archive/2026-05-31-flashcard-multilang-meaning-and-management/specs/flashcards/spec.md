## ADDED Requirements

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
