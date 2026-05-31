## Why

A saved flashcard's `meaning` (and its `source_line_translation`) is filled on
demand in whatever language the learner happened to have selected at that
moment, then stored in a single text column. When the learner later switches the
app language, the deck keeps showing the stale, wrong-language gloss and never
refetches it — the meaning is silently mislabeled. At the same time the deck is
a flat list locked to `updated_at` order with only search and swipe-to-delete,
which makes a growing vocabulary hard to manage. This change makes glosses
language-correct and gives the learner real tools to organize the deck.

## What Changes

- **BREAKING (data):** `flashcards.meaning` and
  `flashcards.source_line_translation` change from `text` to `jsonb` maps keyed
  by translation-target code (`en`, `ja`, `zh-tw`). Existing single-language
  values are dropped on migration and refetched on demand in the correct
  language. This is a shared Supabase schema change consumed by both the web app
  (`../furioke`) and iOS.
- Meaning/translation is fetched **lazily per language**: tapping "Show meaning"
  fetches only the currently selected language; switching the app language
  refetches that language if its key is missing, leaving previously fetched
  languages intact.
- The `/api/translate` vocab path is corrected for Japanese: `ja` resolves to
  the language name "Japanese" (today it leaks the raw code `ja`), and a
  Japanese target produces a monolingual dictionary-style definition rather than
  a translation.
- The iOS deck gains **sort options** (date added, due, A–Z, mastery/level)
  replacing the fixed `updated_at` order, plus **filters** (due now, by song,
  needs review). These are client-only — no schema or web changes.
- Deck search matches against the meaning of the currently selected language
  rather than a single stored string.

## Capabilities

### New Capabilities

<!-- None: all behavior belongs to the existing flashcards capability. -->

### Modified Capabilities

- `flashcards`: glosses become per-language jsonb maps fetched lazily for the
  active language; the deck browse list gains sort and filter controls and
  language-aware search.

## Impact

- **Shared schema:** new migration converting `meaning` and
  `source_line_translation` to `jsonb` (existing values dropped).
- **Web (`../furioke`):** `lib/flashcards/{types,queries,context}.ts`
  (map-shaped gloss, lazy per-language fetch) and `app/api/translate/route.ts`
  (`ja` language name + monolingual definition prompt).
- **iOS (`furioke-ios`):** `Flashcard.swift` (`meaning`/`sourceLineTranslation`
  become `[String: String]`), `FlashcardsService.swift` (jsonb encode/decode),
  `FlashcardsState.swift` (per-language fetch + refetch on language switch),
  `DeckView.swift` (per-language display, sort/filter, language-aware search).
- **Sync:** the jsonb gloss is part of the last-writer-wins row; concurrent
  cross-language fills on different devices may clobber, with the missing
  language refetched on demand (no merge). Captured in design.md.
