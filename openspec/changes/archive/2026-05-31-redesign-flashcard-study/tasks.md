## 1. Mode model & persistence

- [x] 1.1 Add a `StudyMode: String, CaseIterable` enum (`glance`, `read`,
      `hiragana`) with display titles, near the Flashcards feature.
- [x] 1.2 Add a `studyMode` key to `FlashcardDisplayDefaults` and read it in
      `StudyView` via `@AppStorage`, defaulting to `.read`.

## 2. Mode selection UI

- [x] 2.1 Make the Study toolbar menu contain only the inline mode picker (no
      furigana / lyric-line toggles) behind a display-related icon (`eye`), not
      the text-size icon.
- [x] 2.2 Drop the `showFurigana` / `showSourceLine` reads from `StudyView`; the
      back-face always shows the captured lyric with furigana on.

## 3. Mode-driven prompt face

- [x] 3.1 Build the prompt face from the selected mode: Glance = `RubyText` over
      `FuriganaAnnotator.align(surface:reading:)` (per-kanji furigana,
      e.g. いろあ over 色褪); Read = kanji only; Hiragana = the reading.
- [x] 3.2 Build the reveal as the complement — show only the facets the prompt
      withheld (Read adds the reading; Hiragana adds the kanji), always
      including meaning and source line.

## 4. Redesigned study card layout

- [x] 4.1 Rewrite `cardSurface` / `reveal` as a centered prompt + reading +
      meaning stack with clear hierarchy, reusing `Spacing` / `Radii` /
      `Typography` tokens.
- [x] 4.2 Render the source line as a distinct left-aligned source-quote block
      with a leading accent rule; align the translation to the same left edge.
- [x] 4.3 Keep the liquid-glass capsule controls (Reveal / Again / Got it) and
      verify reveal/grade animations and queue behavior are unchanged.

## 5. Highlight the saved word in the source line

- [x] 5.1 Add an optional `highlightWord` to `RubyText` and `highlighted` to
      `RubyCell` (default off) that tints cells whose `wordSurface` matches,
      lighting the kanji run and its okurigana together.
- [x] 5.2 Pass the card's surface as the highlight word to the study back-face
      source line; confirm the lyric surface and deck list are unaffected.

## 6. Verification

- [x] 6.1 Build the app and step through each mode, confirming the prompt face,
      reveal complement, lyric block alignment, and word highlight match the
      spec scenarios.
- [x] 6.2 Confirm the selected mode persists across leaving and re-entering
      study mode, and that the default (`.read`) reproduces today's behavior.
