## Context

`StudyView.swift` renders one centered stack per card: surface (`.largeTitle`),
then on reveal a divider, reading, meaning, the captured lyric line, and its
translation. Two problems:

1. **One trivial direction.** The front always shows the kanji. For a Chinese
   reader the kanji carry the meaning, so the card tests almost nothing — it
   never forces recall of the Japanese reading or the sound→meaning mapping.
2. **Broken alignment.** `RubyFlowLayout` reports `width = proposedWidth` and
   places cells from `bounds.minX` (`RubyFlowLayout.swift:40,61`) — it fills the
   width and hugs the left edge. Everything else on the card is centered, so the
   lyric line looks shoved left and the centered translation under it doesn't
   line up with its own ruby.

The data already supports more: `Flashcard` carries `surface`, `reading`
(hiragana), optional `meaning`, `sourceLine` (pipe-annotated), and
`sourceLineTranslation`. `FuriganaAnnotator` has a private `toHiragana` that
shifts U+30A0–U+30FF scalars down by `0x60`; the inverse is a `+0x60` shift.
Display preferences live in `FlashcardDisplayDefaults` and are read via
`@AppStorage` in both `DeckView` and `StudyView`.

## Goals / Non-Goals

**Goals:**

- A three-rung recognition ladder (Glance / Read / Hiragana) selectable from a
  modes-only Study toolbar menu, session-wide, persisted.
- The mode controls only the prompt face; reveal always completes the full word.
- A modern, minimal card with a fixed, intentional alignment — the lyric becomes
  a distinct left-aligned source-quote block with the saved word highlighted.
- Keep the existing liquid-glass capsule controls.

**Non-Goals:**

- No backend, schema, sync, or `FlashcardSchedule` changes — modes are a local
  display concern over existing data.
- No new "Produce" (meaning → word) direction; the meaning is fetched lazily and
  may be absent, so a meaning-prompt mode is out of scope here.
- No change to the Deck list rendering (`FlashcardDeckRow`).
- No per-card mode switching — selection is per session.

## Decisions

### A single `StudyMode` enum, not orthogonal knobs

Explored two shapes: independent axes (prompt × script) vs. named presets. Chose
**named presets** — one tap on a difficulty ladder is simpler to use and each
rung maps to a clear pedagogical intent. Model it as an enum with a stable raw
value for `@AppStorage`:

```
enum StudyMode: String, CaseIterable {
  case glance    // kanji + per-kanji furigana ruby
  case read      // kanji only           (current behavior, default)
  case hiragana  // reading only, no kanji
}
```

Add a key to `FlashcardDisplayDefaults` (e.g. `studyMode`) and read it via
`@AppStorage` in `StudyView`, defaulting to `.read` so today's behavior is the
default rung. Alternative considered: a dedicated `StudyModeState`/service — too
heavy for a single persisted enum. A katakana rung was considered and dropped:
it is the same recall as Hiragana with only a script change, so it added a
fourth option without a distinct challenge.

### Prompt face is mode-driven; reveal is the complement

The reveal always shows the full word; the mode only chooses which facet is the
prompt and which the front withholds:

| Mode     | Front (prompt)                  | Reveal adds               |
| -------- | ------------------------------- | ------------------------- |
| Glance   | kanji + per-kanji ふりがな ruby | meaning · lyric           |
| Read     | kanji                           | reading · meaning · lyric |
| Hiragana | ひらがな                        | kanji · meaning · lyric   |

Glance reuses `RubyText` over `FuriganaAnnotator.align(surface:reading:)` so
each kanji run carries its own reading (いろあ over 色褪), exactly the lyric
surface's ruby — not the whole reading stacked over the whole word. Read and
Hiragana render a single string. The reveal builds its rows from the same data,
skipping whatever the front already showed.

### Modes-only menu and the highlighted source word

The Study toolbar menu holds only the mode picker (an inline `Picker`) behind a
display-related icon (`eye`), not the text-size icon. The per-deck
`showFurigana` / `showSourceLine` toggles are not surfaced here — the study
back-face always shows the captured lyric with furigana on. The saved word is
pointed out inside that lyric by extending `RubyText` / `RubyCell` with an
optional highlight: cells whose `wordSurface` equals the card's surface are
tinted with the accent. Matching on `wordSurface` (not per-cell `surface`)
lights the kanji run and its okurigana together, and the annotation stores the
full word so the card's surface matches. The param defaults off, leaving the
lyric surface and deck list untouched.

### Layout: centered answer stack + left-aligned source block

Stop mixing alignments. The prompt/reading/meaning stay a centered column. The
source line moves into its own **left-aligned block with a leading accent rule**
(a thin vertical bar / inset), so its left alignment reads as an intentional
blockquote rather than a clash; the translation sits under the ruby on the same
left edge. This both fixes the misalignment and creates a clear "answer vs.
context" hierarchy. Reuse `Spacing` / `Radii` / `Typography` tokens; no new
design tokens. Keep `Surface` + `glassEffect` capsule controls as-is.

## Risks / Trade-offs

- **Hiragana prompts can be ambiguous** (homophone readings map to several
  kanji) → acceptable: the learner self-grades on reveal, and the reveal shows
  the actual kanji, so an "Again" is the natural outcome of a wrong guess.
- **Dropping the furigana / lyric-line toggles from study** means the back-face
  always shows the lyric with furigana → acceptable and intended: the lyric is
  the context the learner wants, and the saved word is highlighted within it.
  The deck list keeps its own toggles.
- **Word highlight depends on `wordSurface` matching the card surface** → holds
  because the captured annotation stores the full word (kanji + okurigana) the
  same way the card surface is keyed; a line where the word never matches simply
  shows no highlight, which is non-fatal.
- **Changing the default away from `.read` would alter existing behavior** →
  default to `.read` so current users see no change until they opt into a mode.

## Open Questions

- None outstanding.
