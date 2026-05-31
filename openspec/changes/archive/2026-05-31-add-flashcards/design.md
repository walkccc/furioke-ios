# Design — iOS flashcards port

## Context

The flashcards feature already exists on the web (`../furioke`,
`feat: add flashcards`). Its layers split cleanly by portability:

| Web layer                                   | Portability                                |
| ------------------------------------------- | ------------------------------------------ |
| `flashcards` table + RLS (migration 009)    | **Reuse as-is** — cross-platform table     |
| `lib/flashcards/schedule.ts` (pure Leitner) | **1:1 Swift port**                         |
| `lib/flashcards/types.ts`, `queries.ts`     | Shapes → Swift `Codable` rows              |
| `/api/flashcards` route                     | **Not used on iOS** (see Decision 1)       |
| `/api/translate` (`mode:'vocab'`)           | Reused for meanings (Decision 4)           |
| `context.tsx` store + React UI              | Re-authored as `FlashcardsState` + SwiftUI |

iOS already has a template for every layer the port needs:
`SavedSongsService`/`LibraryState`/`SongEntity` (server-backed list with a
SwiftData mirror and reconnect sync) and `ReadingCorrectionsService` +
`NowPlayingState.recordOverride`/`syncPendingOverrides` (optimistic local write,
offline queue, last-writer-wins reconcile by `updated_at`).

## Decision 1 — Deck CRUD goes direct to Supabase, not through `/api/flashcards`

The Workers API earns a hop only when it wraps something the client can't hold:
`/api/translate` (Anthropic key + quota), `/api/spotify|apple-music|youtube`
(OAuth secrets / signed dev tokens), `/api/lyrics` (external fetch). The
`flashcards` table is pure CRUD already protected per-user by
`auth.uid() = user_id` RLS — a route would only re-implement that scoping. iOS
already follows this rule: `songs` and `reading_overrides` have **no** Workers
route and are read/written directly through the Supabase Swift client.

**Decision:** `FlashcardsService` talks to the `flashcards` table directly,
modeled on `SavedSongsService`. The `(user_id, surface)` unique constraint makes
save an idempotent upsert (same shape as `songs`'
`(user_id, provider, provider_track_id)`). The web's `/api/flashcards` route
stays for the web and is simply out of scope here.

**Permanence:** the table's insert/update RLS requires a non-anonymous account.
iOS sign-in is Google OAuth, so this always holds and the feature gates on
"signed in" alone — no anonymous branch, no localStorage deck.

## Decision 2 — Deck + study mode live in a fourth tab

The web reaches flashcards from its sidebar; iOS has no sidebar. The deck and
study mode get a fourth `Tab` ("Study", e.g. `rectangle.on.rectangle.angled` /
`square.stack`) in `LiquidGlassTabBar` alongside Library / Search / Settings.
`AppTab` gains a `.study` case. The Study tab is a `NavigationStack` whose root
is the deck list, with study mode pushed (or presented) from it. It clears the
floating mini-player accessory the same way the other tabs do.

## Decision 3 — Full SwiftData mirror + offline queue

Matches `songs`/`reading_overrides` rather than the web's online-only deck, so
the deck renders offline and grades survive a dropped connection.

- **`FlashcardEntity`** in `OfflineCache` mirrors the row columns plus a
  `syncState` (`synced` / `local` / `pendingDelete`), exactly like
  `OverrideEntity`. Keyed by `(userID, surface)`. Purged by `cache.purgeAll()`
  on sign-out (wired through `auth.onSignOutCleanup`).
- **`FlashcardsState`** (`@Observable`, `@MainActor`) owns the in-memory deck +
  a `savedSurfaces: Set<String>` for O(1) marker lookups, seeded from the cache
  on init (like `LibraryState.savedIDs`). The deck view itself can read
  SwiftData via `@Query` so saves reflect immediately.
- **Writes are optimistic**: write the cache + update `savedSurfaces`, then push
  to Supabase; on failure/offline the row stays `local` (or `pendingDelete`) for
  the next reconnect flush. `syncPendingFlashcards()` flushes queued
  upserts/deletes then pulls the server rows and reconciles last-writer-wins by
  `updated_at` — the same ordering `syncPendingOverrides()` uses. It runs on
  launch (when signed in) and on every reconnect via an `observeReconnect`
  registration.

**Grading is a write.** `gradeCard` mutates `level`/`due_at`/`updated_at`; the
graded row goes through the same optimistic-write path, so grading offline
queues and flushes later.

## Decision 4 — Meanings via `/api/translate` in vocab mode

Meaning + source-line translation reuse `/api/translate` (the route that holds
the Anthropic key), so this is the one server hop the feature keeps — consistent
with Decision 1's rule. The web sends `mode: 'vocab'` (glossary mode; the
lyric-translator prompt refuses bare words/lines) and packs the word + the plain
source line into **one** call (`fetchCardContext`), then persists `meaning` and
`sourceLineTranslation` onto the card.

iOS `TranslationService` is whole-body and does **not** send `mode`. The port
adds a vocab path: either a `mode` parameter on `TranslationService.translate`
or a sibling method, sending `mode: "vocab"` and joining the requested lines
with `\n` (one output line per input line). A failure (offline, quota, network)
is non-fatal: the card still shows surface + reading + source line. Fetched
values are cached onto the card (and pushed via the same upsert path) so they
aren't re-fetched.

## Decision 5 — Capture point and source-line fidelity

Capture hangs off the existing long-press → `ReadingEditorCard` flow:

```
RubyTokenCell.onLongPress
   └─> NowPlayingState.beginEditing(surface, reading)   [exists today]
         editingReading holds surface + reading
         NowPlayingState also has music.currentTrack (title/artist)
                                  and lines (the source AnnotatedLine)
```

`ReadingEditorCard` gains a **Save to flashcards** affordance (a lit-glass pill
in the same idiom as its Remember toggle) that reflects `savedSurfaces`
membership and toggles it. `NowPlayingState` is where save is wired, because it
holds the song + line context the card lacks; it builds the capture input and
forwards to `FlashcardsState.toggleSave`.

**Source-line format and ruby rendering.** The web stores `source_line` in
pipe-annotation form (`｜base｜reading｜`, the same notation
`rewriteAnnotationReading` writes) so the card can re-render ruby, and caches
its translation. iOS writes the same format for cross-device parity and
**renders the card's source line as ruby**, reusing the lyric surface's layout.
No new rendering machinery is needed — only a codec between the stored string
and the `[RubyToken]` stream `RubyFlowLayout`/`RubyTokenCell` already consume:

- **Serialize (capture):** walk the captured `AnnotatedLine.tokens`, grouping
  consecutive cells by `wordSurface`; emit `｜wordSurface｜wordReading｜` for a
  word carrying a reading and the bare surface for a plain run. Each cell
  already carries `wordSurface`/`wordReading`, so this round-trips losslessly.
- **Parse (display):** split the stored string on the pipe pattern; bare text
  between matches becomes plain tokens, and each `｜base｜reading｜` runs
  through the existing `FuriganaAnnotator.align(surface:reading:)` for okurigana
  splitting. The reading is stored, so parsing is **synchronous and offline — no
  kuromoji at display time** (unlike the live lyric path).

`RubyLine`/`RubyTokenCell` are currently `private` to `LyricsView`; they'll be
extracted into a shared read-only ruby view the card reuses (the card's variant
drops the long-press-to-edit and tap-to-seek behavior).

**Saved markers.** `RubyTokenCell` consults `FlashcardsState.savedSurfaces` (via
the environment) to mark tokens already in the deck — a subtle underline / dot
in the brand accent, distinct from the active-line emphasis (which is
opacity-only, so a marker can't be confused with it).

## Decision 6 — Schedule port

`FlashcardSchedule.swift` ports `schedule.ts` verbatim:
`INTERVAL_DAYS = [0, 1, 3, 7, 16, 35]`, `MAX_LEVEL`,
`gradeCard(card, grade, now:)`, `isDue(card, now:)`. `now` is injected for
testability (the web does the same), and timestamps are ISO-8601 strings so the
shape round-trips through Supabase unchanged.

## Data shape (Swift)

```swift
struct Flashcard {                 // mirrors lib/flashcards/types.ts
  let surface: String              // dedupe + toggle key
  var reading: String
  var meaning: String?
  var sourceTitle: String?
  var sourceArtist: String?
  var sourceLine: String?          // pipe-annotated for ruby
  var sourceLineTranslation: String?
  var level: Int
  var dueAt: Date
  var createdAt: Date
  var updatedAt: Date
}
enum FlashcardGrade { case again, gotIt }
```

The Supabase row uses snake_case column names (`source_title`, `due_at`, …) via
`CodingKeys`, exactly like `SongRow`/`SongInsert`.

## Risks / open questions

- **Tab-bar density.** Four tabs is the comfortable iOS ceiling; a fifth feature
  later would need rethinking. Acceptable now.
- **`mode:'vocab'` deploy gate.** Not a design unknown — the route already reads
  `mode`, but it gained that handling in the same commit that shipped web
  flashcards. The backend at `FURIOKE_API_BASE_URL` must run that version
  _before_ iOS ships vocab requests; against an older deployment the field is
  silently ignored and single-word meanings come back refused (non-fatal — the
  card still shows surface/reading/source line). Sequence backend first.
- **Cross-device schedule races.** Two devices grading the same card resolve
  last-writer-wins by `updated_at`, same as overrides — acceptable for a study
  schedule.
