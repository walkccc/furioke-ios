## ADDED Requirements

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

## MODIFIED Requirements

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
