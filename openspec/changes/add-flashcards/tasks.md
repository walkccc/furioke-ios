## 1. Model + schedule (pure, testable)

- [ ] 1.1 Add `Furioke/Furioke/Flashcards/Flashcard.swift`: the `Flashcard`
      struct (surface, reading, meaning?, sourceTitle?, sourceArtist?,
      sourceLine?, sourceLineTranslation?, level, dueAt, createdAt, updatedAt)
      and `enum FlashcardGrade { case again, gotIt }`, mirroring
      `../furioke/lib/flashcards/types.ts`.
- [ ] 1.2 Add `Flashcards/FlashcardSchedule.swift` porting
      `lib/flashcards/schedule.ts` verbatim: `INTERVAL_DAYS = [0,1,3,7,16,35]`,
      `maxLevel`, `intervalDays(forLevel:)`, `grade(_:_:now:)`,
      `isDue(_:now:)` — `now` injected for tests.
- [ ] 1.3 Add unit tests for the schedule (promotion cap, "again" reset,
      `isDue` boundary), mirroring `schedule.test.ts`.

## 2. SwiftData mirror in OfflineCache

- [ ] 2.1 Add `FlashcardEntity` to the `OfflineCache` model container: row
      columns plus `userID` and a `syncState` (`synced` / `local` /
      `pendingDelete`), keyed `(userID, surface)`, modeled on `OverrideEntity`.
- [ ] 2.2 Add cache methods mirroring the override/song helpers:
      `flashcards(forUserID:)`, `savedSurfaces(forUserID:)`,
      `upsertFlashcard(...)`, `markFlashcardSynced(...)`,
      `deleteFlashcard(userID:surface:)` (tombstone → `pendingDelete`),
      `pendingFlashcardUpserts(...)`, `pendingFlashcardDeletes(...)`,
      `reconcileFlashcards(userID:serverRows:)` (last-writer-wins by
      `updated_at`).
- [ ] 2.3 Ensure `purgeAll()` clears `FlashcardEntity` so sign-out drops the
      deck (already wired via `auth.onSignOutCleanup`).

## 3. Direct-Supabase service

- [ ] 3.1 Add `Flashcards/FlashcardsService.swift` modeled on
      `SavedSongsService`: `fetchAll()`, `upsert(_:)`
      (`onConflict: "user_id,surface"`), `delete(surface:)` — direct Supabase
      Swift client, `user_id` sent explicitly, snake_case `CodingKeys`.
      No Workers route.

## 4. FlashcardsState (the store)

- [ ] 4.1 Add `Flashcards/FlashcardsState.swift` (`@Observable @MainActor`),
      modeled on `LibraryState` + `NowPlayingState`'s override sync: holds
      `cards`, `savedSurfaces: Set<String>` (seeded from cache), and depends on
      `OfflineCache`, `FlashcardsService`, `AuthService`, `NetworkMonitor`.
- [ ] 4.2 `toggleSave(_:)` (idempotent; removes if present), `remove(surface:)`,
      `grade(surface:_:)` — all optimistic: write cache + update
      `savedSurfaces`, then push via service; on failure/offline leave the row
      queued.
- [ ] 4.3 `sync()` and `syncPendingFlashcards()` (upload queued upserts/deletes
      first, then pull + reconcile by `updated_at`), plus an `observeReconnect`
      registration — same shape as `syncPendingOverrides()`.
- [ ] 4.4 `isSaved(surface:)` / `dueCards(now:)` accessors for the views.
- [ ] 4.5 Construct it in `FuriokeApp.init`, inject into the environment, and
      kick `syncPendingFlashcards()` on launch (signed-in) the way
      `syncPendingOverrides()` is kicked.

## 5. Meaning fetch (vocab translate)

- [ ] 5.1 Extend `TranslationService` with a vocab path: a `mode` parameter (or
      sibling method) that sends `mode: "vocab"` to `/api/translate` and joins
      the requested lines with `\n` (one output line per input line). Confirm
      the deployed route accepts `mode`.
- [ ] 5.2 In `FlashcardsState`, add `fetchCardContext(surface:)` mirroring
      `context.tsx`: request the missing `meaning` (the surface) and/or
      `sourceLineTranslation` (the plain source line) in one call, persist the
      patch via the upsert path; in-flight + cache guards; failure is non-fatal.

## 6. Capture from the lyric surface

- [ ] 6.1 Add a **Save to flashcards** affordance to `ReadingEditorCard` (a
      lit-glass pill like the Remember toggle), shown only when signed in,
      reflecting an `isSaved` input and calling an `onToggleSave` closure.
- [ ] 6.2 In `NowPlayingState`, surface the capture context: build a
      `SaveFlashcardInput` from `editingReading` + `music.currentTrack`
      (title/artist) + the source `AnnotatedLine` (serialized to pipe
      annotation), and forward to `FlashcardsState.toggleSave`. Wire `isSaved`
      from `savedSurfaces`.
- [ ] 6.3 Pass the save affordance through `AppShell.readingEditorOverlay`
      (it already constructs `ReadingEditorCard`).
- [ ] 6.4 Mark saved tokens in `RubyTokenCell`: read `FlashcardsState`
      `savedSurfaces` from the environment and render a marker (brand-accent
      underline/dot) distinct from the opacity-only active-line emphasis; hidden
      when signed out.

## 7. Study tab: deck view + study mode

- [ ] 7.1 Add `.study` to `AppTab` and a fourth `Tab` to `LiquidGlassTabBar`
      (label + SF Symbol), inserted between Search and Settings; host it in
      `AppShell` as a `NavigationStack`.
- [ ] 7.2 Build `Flashcards/DeckView.swift`: searchable list (filter by surface
      / reading / meaning), per-card source context, swipe-to-delete, and an
      `EmptyState` inviting the user to save words from lyrics. Use design
      tokens + `Surface`/`SectionHeader`/`RowItem` primitives.
- [ ] 7.3 Build `Flashcards/StudyView.swift`: present `dueCards`, flip a card to
      reveal reading + meaning + source line (calling `fetchCardContext` on
      reveal), grade Again / Got it via `FlashcardsState.grade`, re-queue
      "Again" in-session, and show a "nothing due" state when empty.
- [ ] 7.4 Render the card's source line as plain text (annotations stripped) in
      v1; leave ruby rendering as a follow-up (annotated form is stored).

## 8. Verify

- [ ] 8.1 Build and run signed in: save a word from the lyric editor → it gets a
      marker, appears in the deck, survives relaunch (loads from cache, then
      reconciles).
- [ ] 8.2 Verify toggle/idempotency: re-saving removes the card and clears the
      marker; saving the same surface twice never duplicates.
- [ ] 8.3 Verify study mode: only due cards show; "Got it" advances level/due,
      "Again" resets and re-queues; "nothing due" state appears when the deck
      has no due cards.
- [ ] 8.4 Verify meanings: revealing a card fetches meaning + source-line
      translation in vocab mode and persists them; a failed/offline fetch leaves
      the card usable.
- [ ] 8.5 Verify offline: grade/save offline → writes queue, then flush and
      reconcile on reconnect with no lost or duplicated cards.
- [ ] 8.6 Verify sign-out clears the deck and markers, and a different account
      never sees the previous user's cards.
