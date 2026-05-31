## MODIFIED Requirements

### Requirement: Long-press a kanji opens the reading editor

The Now Playing surface SHALL open a reading editor when the user long-presses
on a kanji-bearing token in any lyric line. The editor SHALL be presented as a
focus overlay over the lyric surface: the lyric column dims and blurs behind a
dimming scrim, and the editor floats above it as a glass card that echoes the
targeted kanji surface and exposes a focused text field pre-filled with the
current reading. The targeted token MAY give a brief press-down response and a
light haptic when the long-press fires. A short tap on a kanji SHALL retain its
existing line-tap-to-seek behavior; the long-press gesture SHALL NOT be
triggered by short taps, and only kanji-bearing tokens (those carrying a
reading) SHALL be editable. The editor SHALL be dismissible via the system
keyboard's done action, an explicit cancel control, or a tap on the dimming
scrim outside the card.

When the learner is signed in, the editor SHALL additionally present a **Save to
flashcards** affordance, in the same lit-glass idiom as its "Remember this
reading" toggle, that reflects whether the word is already in the deck and
toggles its membership. Triggering it SHALL save the word — its surface,
reading, and the song context (source title, source artist, and the source
lyric line) supplied by `NowPlayingState` — into the flashcard deck, or remove
it if already saved. The save affordance SHALL be independent of the
reading-correction action (saving neither requires nor records a correction) and
SHALL NOT appear when signed out.

#### Scenario: Long-press opens the editor

- **WHEN** the user long-presses on a kanji word in a rendered line
- **THEN** the lyric column dims and a glass editor card appears, echoing the
  kanji surface with a focused field pre-filled with the current hiragana
  reading

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
