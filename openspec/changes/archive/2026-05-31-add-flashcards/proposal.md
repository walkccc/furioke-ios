## Why

The web app just shipped flashcards: a learner reading song lyrics can save an
unfamiliar kanji word and drill it later with spaced repetition. The iOS app
renders the same furigana on the same lyrics but has no way to keep a decoded
word — the moment the song closes, it's gone. The data already lives in a
cross-platform `flashcards` Supabase table (web migration 009) with the exact
schema iOS needs, so this is a port of UI + client logic onto an existing
backend, not new infrastructure.

## What Changes

- Add a **flashcards** capability: a per-user deck of saved kanji words, each
  carrying its surface, reading, an optional meaning, and the song line it was
  captured from, plus a Leitner-style spaced-repetition schedule (`level` +
  `due_at`).
- Let a learner **save a word from the lyrics**: the existing focus-overlay
  reading editor (`ReadingEditorCard`, opened by long-pressing a kanji) gains a
  **Save to flashcards** toggle. The capture carries the song title/artist and
  the source line, which `NowPlayingState` already holds. Re-saving a saved word
  removes it (toggle), and saved words are marked on the lyric surface.
- Add a **fourth tab** ("Study") hosting the **deck view** — a searchable list
  of saved cards with source context, delete, and an empty state — and a **study
  mode** that presents due cards (surface front; reading, meaning, and source
  line on the back) and grades each "Again" / "Got it".
- Persist the deck **directly against the `flashcards` Supabase table** through
  the Supabase Swift client (RLS scopes rows to the user), mirroring
  `SavedSongsService`/`songs` — **not** through a Workers route. A **SwiftData
  mirror + offline write queue** matches the offline story `songs` and
  `reading_overrides` already have: the deck reads from cache, grades work
  offline, and queued writes flush on reconnect.
- Fetch a card's **meaning on demand** from the existing `/api/translate` route
  (glossary `mode: 'vocab'`, JA → the user's language), caching it onto the
  card. This is the one server hop the feature keeps, because that route wraps
  the Anthropic key and per-user quota.

## Non-goals

- No `/api/flashcards` Workers route on iOS. The deck is pure RLS-protected
  CRUD, so it goes direct to Supabase like `songs`/`reading_overrides`; a route
  would only re-implement ownership scoping RLS already enforces.
- No anonymous-account handling. iOS sign-in is Google OAuth, so every session
  is permanent — the web's anonymous-gating requirement collapses to "signed
  in".
- No change to the spaced-repetition algorithm (a straight port of the web's
  Leitner schedule) and no new external dependency.

## Capabilities

### New Capabilities

- `flashcards`: capturing kanji from the lyric surface into a per-user deck,
  persisting it server-side with an offline mirror, browsing/managing the deck,
  and a spaced-repetition study mode.

### Modified Capabilities

- `furigana`: the focus-overlay reading editor gains a save-to-flashcards
  toggle, and the lyric surface marks tokens already in the deck.
- `app-shell`: the tab bar gains a fourth "Study" destination for the deck and
  study mode.

## Impact

- **Data**: reuses the existing `flashcards` table (no new migration). New
  `FlashcardEntity` SwiftData mirror in `OfflineCache`, purged on sign-out.
- **State**: new `FlashcardsState` (`@Observable`, ≈ `LibraryState`) and
  `FlashcardsService` (direct Supabase, ≈ `SavedSongsService`); a Swift port of
  `lib/flashcards/schedule.ts`.
- **UI**: new Study tab with deck + study-mode views; modified
  `ReadingEditorCard`, `LyricsView`/`RubyTokenCell`, and `LiquidGlassTabBar`.
- **APIs**: reuses `/api/translate` (adds `mode: 'vocab'` to the iOS request);
  deck CRUD is direct Supabase.
