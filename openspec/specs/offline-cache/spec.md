## Purpose

This capability gives the iOS app durable offline reading by persisting per-user
data in SwiftData across four entities — `SongEntity`, `LyricBodyEntity`,
`OverrideEntity`, and `TranslationEntity`. Lyric bodies are served through a
read-through cache with a 30-day TTL and a 90-day launch-time janitor that
bounds storage. `SongEntity` mirrors the user's saved `songs` and
`OverrideEntity` mirrors their `reading_overrides`, both reconciled when online
and rendered directly when offline. On sign-out, every per-user cached row is
purged while device-local UI preferences persist.

## Requirements

### Requirement: SwiftData schema for offline cache

The iOS app SHALL persist offline-readable data in SwiftData with four entities
scoped to the signed-in user:

| Entity              | Fields                                                                                   |
| ------------------- | ---------------------------------------------------------------------------------------- |
| `SongEntity`        | `id`, `provider`, `providerTrackId`, `title`, `artist`, `album`, `durationMs`, `savedAt` |
| `LyricBodyEntity`   | `songId`, `lrclibId`, `bodyText` (raw LRC body from `/api/lyrics`), `fetchedAt`          |
| `OverrideEntity`    | `userId`, `kanji`, `reading`, `source` (`local` \| `synced`)                             |
| `TranslationEntity` | `songId`, `language`, `bodyJson`, `modelVersion`, `generatedAt`                          |

Foreign references SHALL be modeled as SwiftData relationships where the entity
model warrants it (e.g., `LyricBodyEntity` belongs to `SongEntity` by `songId`).
Indexes SHALL exist on `songId`, `(songId, language)`, and `(userId, kanji)` to
support read-time lookup in the access layer.

The annotated form of the lyrics (kuromoji output + correction map application)
SHALL NOT be persisted. It is recomputed on every render via the local furigana
annotator from the cached raw LRC body plus the current `OverrideEntity` rows.

#### Scenario: Entities persist across launches

- **WHEN** the app writes a `SongEntity` and a `LyricBodyEntity`, then
  force-quits
- **THEN** on next launch, both entities are readable from SwiftData with their
  fields intact

#### Scenario: No persisted annotated lyrics

- **WHEN** the SwiftData store is inspected
- **THEN** there is no entity carrying tokenized, hashed, or otherwise annotated
  lyric output; the annotated form lives only in memory after the annotator runs
  over `LyricBodyEntity.bodyText`

### Requirement: Read-through cache for lyric bodies

The app SHALL serve lyric-body fetches through a read-through cache against
`LyricBodyEntity`, choosing among the following branches depending on network
state and cache state for the requested track:

- **Online + cache hit + cache fresh (< 30 days):** the cached `bodyText` SHALL
  be returned immediately AND a background revalidation request to `/api/lyrics`
  SHALL be issued. If the revalidation response differs from the cache, the
  cache SHALL be updated and the UI SHALL re-render (which re-runs the local
  furigana annotator against the new body).
- **Online + cache miss or stale:** `/api/lyrics` SHALL be called, the raw LRC
  body returned by the response SHALL be rendered (through the annotator) and
  written to `LyricBodyEntity`.
- **Offline + cache hit:** the cached `bodyText` SHALL be returned and rendered
  through the annotator; no network request SHALL be attempted.
- **Offline + cache miss:** the surface SHALL render a "lyrics unavailable
  offline" state with no retry attempt; no error toast SHALL be shown.

#### Scenario: Cache hit returns immediately

- **WHEN** the user opens a song whose `LyricBodyEntity` is in the cache and
  fresh
- **THEN** the lyrics render in the same frame the surface mounts (tokenization
  runs in memory against the cached body); a background revalidation runs

#### Scenario: Cache miss writes through

- **WHEN** the user opens a song whose `LyricBodyEntity` is not in the cache and
  the device is online
- **THEN** `/api/lyrics` is called, the raw LRC body is rendered through the
  furigana annotator, and the body is written to `LyricBodyEntity` for that song

#### Scenario: Offline cache hit, no network attempt

- **WHEN** the user opens a song whose `LyricBodyEntity` is in the cache and the
  device is offline
- **THEN** the cached body is rendered through the annotator and no
  `/api/lyrics` request is issued

#### Scenario: Offline cache miss is graceful

- **WHEN** the user opens a song whose `LyricBodyEntity` is not in the cache and
  the device is offline
- **THEN** the surface shows a quiet "lyrics unavailable offline" state; no
  retry; no error toast

### Requirement: 30-day TTL for lyric and translation cache

The app SHALL apply a 30-day TTL keyed on `LyricBodyEntity.fetchedAt` and
`TranslationEntity.generatedAt`. Entries older than 30 days SHALL be treated as
stale (forcing a fresh fetch when online; still usable when offline). A periodic
janitor SHALL evict entries older than 90 days on app launch to bound storage.

#### Scenario: Stale entry triggers refetch online

- **WHEN** the user opens a song whose cached body is 35 days old and the device
  is online
- **THEN** the cached entry is treated as stale, `/api/lyrics` is called, and
  the new body replaces the cache entry

#### Scenario: Stale entry still readable offline

- **WHEN** the user opens a song whose cached body is 35 days old and the device
  is offline
- **THEN** the cached body is rendered through the annotator (better stale than
  nothing while offline); no network attempt

#### Scenario: Janitor evicts very old entries

- **WHEN** the app launches and the cache contains entries older than 90 days
- **THEN** those entries are deleted from SwiftData during a background launch
  phase

### Requirement: Library cache mirrors saved songs

`SongEntity` rows SHALL mirror the user's `songs` table from Supabase. On launch
(with network) and on Library tab activation, the app SHALL sync from `songs`
and reconcile by `(provider, providerTrackId)` — inserting new rows, updating
changed metadata, and removing rows the server no longer reports. While offline,
the Library tab SHALL render from `SongEntity` and SHALL NOT attempt sync.

#### Scenario: Library renders offline

- **WHEN** the user opens the Library tab while offline
- **THEN** the saved-song list renders from `SongEntity` with no sync attempt
  and no error

#### Scenario: Reconciliation removes deleted rows

- **WHEN** a song was deleted on the web app and the iOS app comes online and
  syncs
- **THEN** the matching `SongEntity` is removed from local storage and the
  Library list no longer shows that song

### Requirement: Override cache reflects reading_overrides

`OverrideEntity` rows SHALL mirror the user's `reading_overrides` table. Local
edits (long-press inline editor) SHALL be written to `OverrideEntity` with
`source = local` immediately, then POSTed to the server in the background.
Server-side overrides synced down SHALL be written with `source = synced`. On
successful server write, the local row's `source` SHALL transition to `synced`.

The local furigana annotator SHALL read all `OverrideEntity` rows when
constructing its `CorrectionMap` so an edit takes visible effect on the next
render pass.

#### Scenario: Local edit is optimistic

- **WHEN** the user records an override on Now Playing while offline
- **THEN** the override is written to `OverrideEntity` with `source = local` and
  applied to the on-screen rendering immediately (the furigana annotator re-runs
  with the updated map); an upload is queued for the next online tick

#### Scenario: Queued upload syncs on reconnect

- **WHEN** the device reconnects after an offline override was recorded
- **THEN** the queued upload runs, the server persists the row, and the local
  `OverrideEntity.source` becomes `synced`

### Requirement: Sign-out purges per-user cache

When the user signs out, the app SHALL purge every `SongEntity`,
`LyricBodyEntity`, `OverrideEntity`, and `TranslationEntity` row scoped to that
user. Other UI preferences (theme, language, last-active provider) SHALL persist
as device-local settings.

#### Scenario: Sign-out clears per-user cache

- **WHEN** the user signs out
- **THEN** all four entity types are emptied for that user's scope before the
  app transitions to the sign-in surface
