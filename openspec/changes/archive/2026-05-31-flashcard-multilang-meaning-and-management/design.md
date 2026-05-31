## Context

Flashcards are a shared capability: one Supabase `flashcards` table (migration
`009_flashcards.sql`) is read and written directly — RLS-scoped — by both the
web app (`../furioke`, `lib/flashcards/*`) and the iOS client (`furioke-ios`,
`Furioke/Flashcards/*`). The row shape, column names, and the
`(user_id, surface)` upsert contract are mirrored on both sides.

Today `meaning` and `source_line_translation` are single `text` columns. They
are filled lazily: tapping "Show meaning" (or showing a card with a source line)
calls `/api/translate` in `vocab` mode with the learner's _current_
`translationTarget` (`en`, `ja`, or `zh-tw`) and stores the result. The stored
string carries no record of which language it is in. When the learner switches
the app language, the deck shows the old string unchanged — wrong language,
never refetched.

The deck browse surface (iOS `DeckView`, web list) is ordered by
`updated_at DESC` with only free-text search and swipe-to-delete. Study
sequencing is independent: it pulls `dueCards()` by the Leitner schedule, not by
list order.

Supported languages are `en`, `ja`, and `zh-tw` (Traditional Chinese; `zhHant`).
These codes already exist as `translationTarget` values on both clients and as
the `/api/translate` target.

## Goals / Non-Goals

**Goals:**

- Store glosses per language so the displayed meaning always matches the active
  app language.
- Fetch glosses lazily, one language at a time, preserving previously fetched
  languages.
- Fix the `ja` translate path so Japanese glosses are real monolingual
  definitions.
- Give the iOS deck sort and filter controls and language-aware search, with no
  schema or web changes.
- Keep web and iOS in lockstep on the shared row shape.

**Non-Goals:**

- Manual drag-to-reorder or a persistent `sort_order`/pin column (explicitly
  chosen: sort options instead).
- Changing the spaced-repetition schedule or what study mode selects.
- Eagerly translating all three languages on save (would triple quota usage).
- Server-side merge of concurrent cross-language gloss writes (see Risks).
- Migrating existing gloss strings into a language bucket (existing values are
  dropped; they refetch on demand).

## Decisions

### Decision 1: `meaning` and `source_line_translation` become `jsonb` maps

Both columns change from `text` to `jsonb`, keyed by translation-target code:

```
meaning = { "en": "to continue", "ja": "つづくこと", "zh-tw": "繼續" }
```

Keys are exactly the existing `translationTarget` codes — reuse `"zh-tw"`, do
**not** introduce a separate `"zhHant"` key, because the whole stack (the
translate route, both clients' `translationTarget`) already speaks `"zh-tw"`.
Maps are sparse: only fetched languages are present.

**Alternatives considered:**

- _Per-language columns_ (`meaning_en`, `meaning_ja`, …): explicit and typed,
  but 6 columns for 2 fields × 3 languages and a migration to add any future
  language. Rejected for rigidity.
- _Side table_ (`flashcard_meanings(flashcard_id, lang, …)`): fully normalized,
  but adds join/aggregate cost to every deck read and write for a small app with
  a fixed language set. Rejected as over-built.
- _JSONB map_ (chosen): sparse, add a language with no migration, and maps
  almost 1:1 onto the existing "is the gloss missing?" fetch logic — it just
  becomes "is `map[lang]` missing?".

### Decision 2: Existing gloss values are dropped, not migrated

The migration replaces existing `text` values with empty maps (`'{}'::jsonb`).
We never recorded which language an existing string was in, so any back-fill
would be a guess. Dropping is lossy but cheap and correct: the next time a card
is shown in language L, `map[L]` is missing, so it refetches. One-time quota
cost, no ambiguity, no dual display code path.

### Decision 3: Lazy per-language fetch, refetch on language switch

The fetch path keys off the active language:

- Tap "Show meaning" → fetch only `translationTarget` → set `map[target]`.
- Card shown / language switched → if `map[activeTarget]` is missing for a
  needed field, fetch just that language.
- Languages already in the map are never refetched.

This preserves the current on-demand model and the per-surface in-flight guard.
It also bounds quota: a card costs at most one translate call per language the
learner actually views.

### Decision 4: `/api/translate` Japanese correction

`targetLanguageName('ja')` returns the raw `"ja"` today, producing the nonsense
prompt "Japanese-to-ja dictionary." Fix: `ja` → `"Japanese"`. Additionally, for
a `ja` target the `vocab` prompt SHALL produce a monolingual Japanese
dictionary-style definition (the "meaning" of a Japanese word in Japanese is a
definition, not a translation). Lyric (non-vocab) `ja` behavior is unchanged.

### Decision 5: iOS deck management is sort + filter, client-only

`DeckView` gains a sort selector (date added, due, A–Z, mastery/level) replacing
the fixed `updated_at` order, and filters (due now, by song, needs review).
These read existing card fields, persist the chosen sort/filter in
`@AppStorage`, and require no schema or web change. Search matches the meaning
of the active language (`map[activeTarget]`) plus surface and reading.

## Risks / Trade-offs

- **Concurrent cross-language fills clobber under last-writer-wins** → The jsonb
  gloss is part of the row; two devices in different languages filling different
  keys offline will, on reconcile, have the later `updatedAt` overwrite the
  whole map. Mitigation: accept it — the lost language's key is simply missing
  and refetches on demand (consistent with Decision 2). A server-side `||` merge
  is possible later but is out of scope.
- **One-time refetch cost after migration** → Every previously-glossed card
  refetches its meaning the first time it is viewed post-migration, consuming
  translate quota. Mitigation: lazy fetch spreads this across normal use; only
  viewed cards pay.
- **Web and iOS must ship the row-shape change together** → A client still
  expecting `text` will fail to decode `jsonb`. Mitigation: treat the
  migration + both client decoders as one coordinated release; sequence in the
  migration plan.
- **`zhHant` vs `zh-tw` key drift** → Using the wrong key string would silently
  never hit the cache. Mitigation: keys are defined as the existing
  `translationTarget` codes, asserted in the spec.

## Migration Plan

1. Land the Supabase migration converting both columns to `jsonb` with `'{}'`
   default (existing values dropped).
2. Release the web (`../furioke`) gloss-map + lazy-fetch changes and the
   `/api/translate` `ja` fix.
3. Release the iOS client decoding/encoding the jsonb maps and fetching per
   active language.
4. Steps 2 and 3 must not precede step 1; clients reading the old `text` shape
   after migration, or the new `jsonb` shape before it, will fail to decode.
   Coordinate as one rollout.

Rollback: revert the migration (column back to `text`); both clients must roll
back in the same window. Since glosses are derivable on demand, no gloss data
needs preserving across a rollback.

## Open Questions

- None blocking. A future server-side jsonb merge to avoid cross-language
  clobber can be revisited if multi-device, multi-language use proves common.
