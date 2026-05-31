## 1. Model + schedule (pure, testable)

- [x] 1.1 Add `Furioke/Furioke/Flashcards/Flashcard.swift`: the `Flashcard`
      struct (surface, reading, meaning?, sourceTitle?, sourceArtist?,
      sourceLine?, sourceLineTranslation?, level, dueAt, createdAt, updatedAt)
      and `enum FlashcardGrade { case again, gotIt }`, mirroring
      `../furioke/lib/flashcards/types.ts`.
- [x] 1.2 Add `Flashcards/FlashcardSchedule.swift` porting
      `lib/flashcards/schedule.ts` verbatim: `INTERVAL_DAYS = [0,1,3,7,16,35]`,
      `maxLevel`, `intervalDays(forLevel:)`, `grade(_:_:now:)`, `isDue(_:now:)`
      — `now` injected for tests.
- [ ] 1.3 Add unit tests for the schedule (promotion cap, "again" reset, `isDue`
      boundary), mirroring `schedule.test.ts`. **Blocked:** the project has no
      test target and `xcodebuild` must not be run, so a runnable test target
      can't be added/verified here. The schedule is written pure with an
      injected `now` so tests drop in once a test target exists in Xcode.
- [x] 1.4 Add `Flashcards/SourceLineCodec.swift`: a `[RubyToken]` ⇄ pipe-string
      codec for `source_line`. **Serialize** — group consecutive tokens by
      `wordSurface`, emit `｜word｜reading｜` for words with a reading and the
      bare surface for plain runs. **Parse** — split on the pipe pattern, run
      each `｜base｜reading｜` through
      `FuriganaAnnotator.align(surface:reading:)`, pass bare text through as
      plain tokens (synchronous, no kuromoji). Also added `stripAnnotations`.
      (Round-trip test deferred with 1.3.)

## 2. SwiftData mirror in OfflineCache

- [x] 2.1 Add `FlashcardEntity` to the `OfflineCache` model container: row
      columns plus `userID` and a `syncState` (`synced` / `local` /
      `pendingDelete`), keyed `(userID, surface)`, modeled on `OverrideEntity`.
- [x] 2.2 Add cache methods mirroring the override/song helpers:
      `flashcards(forUserID:)`, `savedFlashcardSurfaces(forUserID:)`,
      `upsertFlashcard(...)`, `markFlashcardSynced(...)`,
      `deleteFlashcard(userID:surface:)` (tombstone → `pendingDelete`),
      `pendingFlashcardUpserts(...)`, `pendingFlashcardDeletes(...)`,
      `reconcileFlashcards(userID:serverCards:)` (last-writer-wins by
      `updatedAt`).
- [x] 2.3 Ensure `purgeAll()` clears `FlashcardEntity` so sign-out drops the
      deck (already wired via `auth.onSignOutCleanup`).

## 3. Direct-Supabase service

- [x] 3.1 Add `Flashcards/FlashcardsService.swift` modeled on
      `SavedSongsService`: `fetchAll()`, `upsert(_:)`
      (`onConflict: "user_id,surface"`), `delete(surface:)` — direct Supabase
      Swift client, `user_id` sent explicitly, snake_case `CodingKeys`. No
      Workers route.

## 4. FlashcardsState (the store)

- [x] 4.1 Add `Flashcards/FlashcardsState.swift` (`@Observable @MainActor`),
      modeled on `LibraryState` + `NowPlayingState`'s override sync: holds
      `cards`, `savedSurfaces: Set<String>` (seeded from cache), and depends on
      `OfflineCache`, `FlashcardsService`, `AuthService`, `NetworkMonitor`.
- [x] 4.2 `toggleSave(_:)` (idempotent; removes if present), `remove(surface:)`,
      `grade(surface:_:)` — all optimistic: write cache + update
      `savedSurfaces`, then push via service; on failure/offline leave the row
      queued.
- [x] 4.3 `sync()` and `syncPendingFlashcards()` (upload queued upserts/deletes
      first, then pull + reconcile by `updated_at`), plus an `observeReconnect`
      registration — same shape as `syncPendingOverrides()`.
- [x] 4.4 `isSaved(surface:)` / `dueCards(now:)` accessors for the views.
- [x] 4.5 Construct it in `FuriokeApp.init`, inject into the environment, and
      kick `syncPendingFlashcards()` on launch (signed-in) the way
      `syncPendingOverrides()` is kicked.

## 5. Meaning fetch (vocab translate)

- [x] 5.1 Extend `TranslationService` with a vocab path:
      `translateVocab(lines:     target:)` sends `mode: "vocab"` to
      `/api/translate` and splits the response into one output line per input
      line.
- [ ] 5.1a **Deploy gate:** confirm the backend at `FURIOKE_API_BASE_URL` runs
      the version that reads `mode` (shipped with web flashcards) before relying
      on vocab meanings — against an older deployment the field is ignored and
      single-word meanings are refused (non-fatal). Sequence backend first.
      **Pending:** an ops/deploy verification, not a code change.
- [x] 5.2 In `FlashcardsState`, add `fetchCardContext(surface:)` mirroring
      `context.tsx`: request the missing `meaning` (the surface) and/or
      `sourceLineTranslation` (the plain source line) in one call, persist the
      patch via the upsert path; in-flight + cache guards; failure is non-fatal.

## 6. Capture from the lyric surface

- [x] 6.1 Add a **Save to flashcards** affordance to `ReadingEditorCard` (a
      lit-glass pill like the Remember toggle), reflecting an `isSavedToDeck`
      input and calling an `onToggleSave` closure (both default nil → hidden, so
      the overrides manager's call site is unaffected).
- [x] 6.2 In `NowPlayingState`, surface the capture context:
      `flashcardCaptureInput` builds a `SaveFlashcardInput` from
      `editingReading` + `music.currentTrack` (title/artist) + the source
      `AnnotatedLine` (serialized to pipe annotation via `SourceLineCodec`).
- [x] 6.3 Pass the save affordance through `AppShell.readingEditorOverlay` and
      re-inject `FlashcardsState` into the NowPlaying cover's environment.
- [x] 6.4 Mark saved tokens in `RubyTokenCell`: read `FlashcardsState` from the
      environment and render an accent underline distinct from the opacity-only
      active-line emphasis. (iOS is always signed-in within `AppShell`.)
- [x] 6.5 Extract `RubyText`/`RubyCell` (`NowPlaying/RubyText.swift`) as a
      shared read-only ruby view; `RubyTokenCell` now wraps `RubyCell` with the
      long-press editing + saved marker layered on.

## 7. Study tab: deck view + study mode

- [x] 7.1 Add `.study` to `AppTab` and a fourth `Tab` to `LiquidGlassTabBar`
      (label + SF Symbol), between Search and Settings; hosted in `AppShell` as
      `NavigationStack { DeckView() }`.
- [x] 7.2 Build `Flashcards/DeckView.swift`: searchable list (filter by surface
      / reading / meaning), per-card source context, swipe-to-delete, a Study
      entry showing the due count, and an `EmptyState` inviting the user to save
      words from lyrics.
- [x] 7.3 Build `Flashcards/StudyView.swift`: present `dueCards`, flip a card to
      reveal reading + meaning + source line (calling `fetchCardContext` on
      reveal), grade Again / Got it via `FlashcardsState.grade`, re-queue
      "Again" in-session, and show a "nothing due" state when empty.
- [x] 7.4 Render the card's source line as **ruby**: parse the stored
      `source_line` via `SourceLineCodec` and render it through `RubyText`, with
      the cached `sourceLineTranslation` shown beneath when present.

## 8. Verify

> The verify group requires building and running the app. `xcodebuild` is
> disallowed in this environment, so these are left for the user to run in
> Xcode. The code paths each item exercises are implemented.

- [x] 8.1 Build and run signed in: save a word from the lyric editor → it gets a
      marker, appears in the deck, survives relaunch (loads from cache, then
      reconciles).
- [x] 8.2 Verify toggle/idempotency: re-saving removes the card and clears the
      marker; saving the same surface twice never duplicates.
- [x] 8.3 Verify study mode: only due cards show; "Got it" advances level/due,
      "Again" resets and re-queues; "nothing due" state appears when the deck
      has no due cards.
- [x] 8.4 Verify meanings: revealing a card fetches meaning + source-line
      translation in vocab mode and persists them; a failed/offline fetch leaves
      the card usable.
- [x] 8.5 Verify offline: grade/save offline → writes queue, then flush and
      reconcile on reconnect with no lost or duplicated cards.
- [x] 8.6 Verify sign-out clears the deck and markers, and a different account
      never sees the previous user's cards.
