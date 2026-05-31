## Why

The study card is hard to use and visually broken. It tests only one direction
(see the kanji, recall the reading), which is the _easy_ direction for a Chinese
reader — the kanji give the meaning away for free, so the card never exercises
real Japanese reading recall. And the revealed back is a pile of mismatched
alignments: the prompt, reading, meaning, and translation are centered while the
captured lyric line (`RubyFlowLayout`, which fills its width and hugs the left
edge) is left-aligned, so the lyric looks shoved against the card edge and the
translation under it doesn't even line up with its own ruby.

## What Changes

- Add **study display modes** — a three-rung difficulty ladder selected in the
  Study toolbar menu, applied for the whole session: **Glance** (kanji +
  per-kanji furigana, recognize only), **Read** (kanji, produce the reading —
  today's behavior), **Hiragana** (reading only, no kanji crutch — the challenge
  for Chinese readers, who lose the kanji shortcut). The mode controls only the
  _prompt face_; the reveal always completes the full word (kanji · reading ·
  meaning · lyric).
- Make the Study toolbar menu contain **only** the modes (a display-related
  icon, not the text-size icon) — the per-deck furigana / lyric-line toggles are
  dropped from this screen; the study back-face always shows the captured lyric.
- Persist the selected mode in `@AppStorage` so it survives across sessions.
- Rewrite the study card to a modern, minimal layout: a centered prompt/reading/
  meaning stack, and the captured lyric rendered as a distinct **left-aligned
  source-quote block** (a leading accent rule) with the **saved word
  highlighted** inside the line, so its alignment reads as intentional instead
  of clashing with the centered stack. The translation aligns to the lyric's
  left edge.
- Keep the existing liquid-glass capsule controls (Reveal / Again / Got it).

## Capabilities

### New Capabilities

<!-- none; this extends the existing flashcards study experience -->

### Modified Capabilities

- `flashcards`: the study-mode requirement gains a selectable recognition ladder
  (Glance / Read / Phonetic / Katakana) that determines the prompt face, with
  the reveal completing the full word; the source line renders as a distinct
  left-aligned quote block on the redesigned study card.

## Impact

- `Furioke/Furioke/Flashcards/StudyView.swift` — rewritten: mode selection in
  the toolbar, mode-dependent prompt face, redesigned reveal layout, lyric
  source block.
- `Furioke/Furioke/Flashcards/DeckView.swift` — `FlashcardDisplayDefaults` gains
  a study-mode key; the deck's existing display toggles are unchanged.
- `Furioke/Furioke/NowPlaying/RubyText.swift` — `RubyText` / `RubyCell` gain an
  optional `highlightWord` / `highlighted` to tint the saved word's cells;
  default off, so the lyric surface and deck list are unaffected.
- No backend, schema, or sync changes — modes are a local display concern over
  the existing `Flashcard` data.
