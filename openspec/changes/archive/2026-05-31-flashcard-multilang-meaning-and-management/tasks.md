## 1. Shared schema migration

- [x] 1.1 Add migration (`supabase/migrations/011_flashcard_gloss_jsonb.sql`)
      converting `flashcards.meaning` and `flashcards.source_line_translation`
      from `text` to `jsonb`, defaulting to `'{}'::jsonb` and dropping existing
      values
- [x] 1.2 Update the migration's column comments to document the per-language
      map shape (keys `en` / `ja` / `zh-tw`) and that existing values are
      intentionally dropped for on-demand refetch

## 2. Web (`../furioke`) gloss map

- [x] 2.1 Change `lib/flashcards/types.ts` `Flashcard.meaning` and
      `sourceLineTranslation` to a `GlossMap`
      (`Record<TranslationTarget, string>`); add `localeToTarget` + `glossFor`
      helpers
- [x] 2.2 Update `lib/flashcards/queries.ts` `rowToCard`/`cardToRow` to pass the
      jsonb maps through (default `{}` when null)
- [x] 2.3 Update `lib/flashcards/context.tsx` `fetchCardContext` to fetch only
      the active `target`, read/write `map[target]`, skip present keys, and key
      the in-flight guard + session `definitionCache` by language
- [x] 2.4 Update web deck rendering (`flashcard-face.tsx`, `deck-list.tsx`) to
      display/search `glossFor(card.meaning, target)`; the per-card on-appear
      `fetchCardContext` refetches on locale change

## 3. Web translate route — Japanese

- [x] 3.1 In `app/api/translate/route.ts`, make `targetLanguageName('ja')`
      return `"Japanese"`
- [x] 3.2 For a `ja` vocab target, use a monolingual Japanese (国語) definition
      prompt; lyric (non-vocab) `ja` behavior unchanged

## 4. iOS model & service

- [x] 4.1 Change `Flashcard.swift` `meaning` and `sourceLineTranslation` to
      `[String: String]`; update the doc comment
- [x] 4.2 Update `FlashcardsService.swift` `FlashcardRow`/`FlashcardInsert` to
      decode/encode the jsonb columns as maps (default empty map when null);
      also update `FlashcardEntity` (cache) to store the maps as JSON in the
      existing `String?` columns, avoiding a SwiftData migration
- [x] 4.3 Add `Flashcard.meaning(for:)` / `sourceLineTranslation(for:)`
      active-language helpers used by the views

## 5. iOS lazy per-language fetch

- [x] 5.1 Update `FlashcardsState.fetchCardContext` to fetch only the active
      `translationTarget` and set `map[target]`, preserving other languages
- [x] 5.2 Decide a needed gloss is "missing" via `meaning(for: target) == nil`;
      key the in-flight guard by `(target, surface)`
- [x] 5.3 Refetch the active language on a language switch for the revealed
      study card (`StudyView.onChange`); the deck's per-row "Show meaning"
      affordance reappears for the new language

## 6. iOS deck display, sort, filter, search

- [x] 6.1 Update `DeckView` `FlashcardDeckRow` to display `meaning(for: target)`
      and show "Show meaning" when that key is absent
- [x] 6.2 Add a `DeckSort` selector (date added, due, A–Z by reading, mastery)
      persisted in `@AppStorage`; apply it to the deck list
- [x] 6.3 Add `DeckFilter` (all, due now, needs review, by source song) layered
      on top of search
- [x] 6.4 Update the deck search predicate to match surface, reading, and
      `meaning(for: target)` only
- [x] 6.5 Confirm study-mode sequencing still uses `dueCards()` by schedule and
      is unaffected by the deck sort (verified by reading: `StudyView` seeds
      `queue` from `flashcards.dueCards()`)

## 7. Verification

- [x] 7.3 Web and iOS produce the same jsonb shape by construction (both a JSON
      object of target→gloss); web `tsc` clean, iOS `xcodebuild` succeeds, full
      web test suite (59) green
- [x] 7.4 Deck sort/filter/search compile and match the spec logic; study-order
      non-interference confirmed by code (group 6.5)
- [ ] 7.1 RUNTIME (pending): with the app signed in, fetch in each of `en` /
      `ja` / `zh-tw`, confirm each stores under its own key and switching
      language refetches only the missing one — needs the live translate API
- [ ] 7.2 RUNTIME (pending): after applying migration 011, confirm a
      previously-glossed card shows "Show meaning" and refetches on demand —
      needs the migration applied to a real database
