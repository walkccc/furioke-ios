import Foundation
import SwiftData

/// Owns the SwiftData store for offline reading and exposes the typed read/write
/// accessors the repositories use. Root-owned and
/// `@MainActor`, so every access goes through `mainContext` on one actor and no
/// `@Model` instance ever crosses an actor boundary — callers extract plain
/// value types before returning.
@MainActor
final class OfflineCache {
  /// Freshness window. Entries older than this are *stale*: refetched when online,
  /// still served when offline (better stale than blank). Mirrors the web app's
  /// 30-day IndexedDB translation cache.
  static let ttl: TimeInterval = 30 * 24 * 60 * 60
  /// Hard retention. The launch janitor evicts anything older to bound storage.
  static let maxAge: TimeInterval = 90 * 24 * 60 * 60

  let container: ModelContainer
  private var context: ModelContext {
    container.mainContext
  }

  init(inMemory: Bool = false) {
    let schema = Schema([
      SongEntity.self,
      LyricBodyEntity.self,
      OverrideEntity.self,
      TranslationEntity.self,
      FlashcardEntity.self,
    ])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
    do {
      container = try ModelContainer(for: schema, configurations: configuration)
    } catch {
      // A corrupt or migration-incompatible store must never block launch. Fall
      // back to an in-memory store: the cache starts empty and refills online.
      // Trap loudly in debug — a *silent* fallback here makes the entire cache
      // non-persistent across launches (local-only data like lyrics never
      // survives), while server-synced data masks it by refilling each launch.
      assertionFailure("OfflineCache: persistent store failed to open: \(error)")
      container = try! ModelContainer(
        for: schema,
        configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
      )
    }
  }

  // MARK: Lyric bodies

  func lyricBody(forSongID songID: String) -> LyricBodyEntity? {
    var descriptor = FetchDescriptor<LyricBodyEntity>(predicate: #Predicate { $0.songID == songID })
    descriptor.fetchLimit = 1
    return try? context.fetch(descriptor).first
  }

  func upsertLyricBody(songID: String, lrclibID: String?, body: String, fetchedAt: Date = .now) {
    if let existing = lyricBody(forSongID: songID) {
      existing.bodyText = body
      existing.lrclibID = lrclibID
      existing.fetchedAt = fetchedAt
    } else {
      context.insert(LyricBodyEntity(
        songID: songID,
        lrclibID: lrclibID,
        bodyText: body,
        fetchedAt: fetchedAt
      ))
    }
    try? context.save()
  }

  // MARK: Saved songs

  /// Track ids (`provider:providerTrackID`) of every saved song, for fast
  /// "already saved" checks without re-querying per row.
  func savedSongIDs() -> Set<String> {
    let rows = (try? context.fetch(FetchDescriptor<SongEntity>())) ?? []
    return Set(rows.map(\.id))
  }

  func song(forID id: String) -> SongEntity? {
    var descriptor = FetchDescriptor<SongEntity>(predicate: #Predicate { $0.id == id })
    descriptor.fetchLimit = 1
    return try? context.fetch(descriptor).first
  }

  /// Reconcile the local mirror with the server's `songs` rows:
  /// insert new, update changed metadata, and delete rows the server no longer
  /// reports. Matching is by track id (`provider:providerTrackID`).
  func reconcileSongs(_ songs: [SavedSong]) {
    let existing = (try? context.fetch(FetchDescriptor<SongEntity>())) ?? []
    let byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { current, _ in current })
    var serverIDs: Set<String> = []
    for song in songs {
      serverIDs.insert(song.id)
      if let entity = byID[song.id] {
        entity.title = song.title
        entity.artist = song.artist ?? ""
        entity.album = song.album
        entity.artworkURL = song.artworkURL
        entity.durationMs = song.durationMs ?? 0
        entity.savedAt = song.savedAt
      } else {
        context.insert(song.asEntity)
      }
    }
    for entity in existing where !serverIDs.contains(entity.id) {
      context.delete(entity)
    }
    try? context.save()
  }

  /// Drop a single saved song from the local store (after an unsave). Absent is a
  /// no-op; the `@Query`-backed Library list updates from the deletion.
  func deleteSong(id: String) {
    guard let entity = song(forID: id) else { return }
    context.delete(entity)
    try? context.save()
  }

  /// Mirror a single saved song into the local store (after an optimistic save).
  func upsertSong(_ saved: SavedSong) {
    if let entity = song(forID: saved.id) {
      entity.title = saved.title
      entity.artist = saved.artist ?? ""
      entity.album = saved.album
      entity.artworkURL = saved.artworkURL
      entity.durationMs = saved.durationMs ?? 0
      entity.savedAt = saved.savedAt
    } else {
      context.insert(saved.asEntity)
    }
    try? context.save()
  }

  // MARK: Translations

  func translation(forSongID songID: String, language: String) -> TranslationEntity? {
    var descriptor = FetchDescriptor<TranslationEntity>(
      predicate: #Predicate { $0.songID == songID && $0.language == language }
    )
    descriptor.fetchLimit = 1
    return try? context.fetch(descriptor).first
  }

  func upsertTranslation(
    songID: String,
    language: String,
    bodyJson: String,
    modelVersion: String,
    generatedAt: Date = .now
  ) {
    if let existing = translation(forSongID: songID, language: language) {
      existing.bodyJson = bodyJson
      existing.modelVersion = modelVersion
      existing.generatedAt = generatedAt
    } else {
      context.insert(
        TranslationEntity(
          songID: songID,
          language: language,
          bodyJson: bodyJson,
          modelVersion: modelVersion,
          generatedAt: generatedAt
        )
      )
    }
    try? context.save()
  }

  // MARK: Overrides

  /// All of a user's overrides as a `surface → reading` map, for the furigana
  /// annotator's `CorrectionMap`. Rows tombstoned for deletion (`.pendingDelete`)
  /// are excluded so a deleted reading stops annotating on the next song load.
  func overrides(forUserID userID: String) -> [String: String] {
    let deletedSource = OverrideEntity.Source.pendingDelete.rawValue
    let descriptor = FetchDescriptor<OverrideEntity>(
      predicate: #Predicate { $0.userID == userID && $0.source != deletedSource }
    )
    let rows = (try? context.fetch(descriptor)) ?? []
    return Dictionary(
      rows.map { ($0.surface, $0.reading) },
      uniquingKeysWith: { _, latest in latest }
    )
  }

  /// Full override rows for the management screen, as plain value types sorted by
  /// surface for stable display. `.pendingDelete` tombstones are excluded — they are
  /// on their way out.
  func overrideRows(forUserID userID: String) -> [ReadingOverride] {
    let deletedSource = OverrideEntity.Source.pendingDelete.rawValue
    let localSource = OverrideEntity.Source.local.rawValue
    let descriptor = FetchDescriptor<OverrideEntity>(
      predicate: #Predicate { $0.userID == userID && $0.source != deletedSource },
      sortBy: [SortDescriptor(\.surface)]
    )
    let rows = (try? context.fetch(descriptor)) ?? []
    return rows.map {
      ReadingOverride(
        surface: $0.surface,
        reading: $0.reading,
        isPendingSync: $0.source == localSource
      )
    }
  }

  /// Delete an override the user removed from the management screen. A row never
  /// uploaded (`.local`) is dropped outright — the server never saw it. A `.synced`
  /// row is tombstoned (`.pendingDelete`) instead of dropped, so a later server pull
  /// can't resurrect it; the reconnect flush issues the `DELETE` and then calls
  /// `removeOverride`. Used for the offline / deferred path.
  func deleteOverride(userID: String, surface: String) {
    guard let existing = overrideRow(userID: userID, surface: surface) else { return }
    if existing.source == OverrideEntity.Source.local.rawValue {
      context.delete(existing)
    } else {
      existing.source = OverrideEntity.Source.pendingDelete.rawValue
    }
    try? context.save()
  }

  /// Hard-remove an override row locally with no tombstone. Called after a server
  /// `DELETE` succeeds (online delete, or a drained `.pendingDelete`).
  func removeOverride(userID: String, surface: String) {
    guard let existing = overrideRow(userID: userID, surface: surface) else { return }
    context.delete(existing)
    try? context.save()
  }

  /// Surfaces of overrides tombstoned for deletion, for the reconnect flush to drain
  /// as Supabase `DELETE`s.
  func pendingDeletes(forUserID userID: String) -> [String] {
    let deletedSource = OverrideEntity.Source.pendingDelete.rawValue
    let descriptor = FetchDescriptor<OverrideEntity>(
      predicate: #Predicate { $0.userID == userID && $0.source == deletedSource }
    )
    let rows = (try? context.fetch(descriptor)) ?? []
    return rows.map(\.surface)
  }

  /// Record (or update) a personal override locally. An inline-editor edit writes
  /// `source = .local` immediately so the rendering reflects it before any upload;
  /// a sync-down from the server writes `source = .synced`. `updatedAt` stamps the
  /// edit time so a later server pull can resolve conflicts last-writer-wins.
  func upsertOverride(
    userID: String,
    surface: String,
    reading: String,
    source: OverrideEntity.Source,
    updatedAt: Date = .now
  ) {
    if let existing = overrideRow(userID: userID, surface: surface) {
      existing.reading = reading
      existing.source = source.rawValue
      existing.updatedAt = updatedAt
    } else {
      context.insert(OverrideEntity(
        userID: userID,
        surface: surface,
        reading: reading,
        source: source,
        updatedAt: updatedAt
      ))
    }
    try? context.save()
  }

  /// Reconcile the local override mirror with the server's `reading_overrides`
  /// rows, resolving conflicts last-writer-wins by `updatedAt`. Run *after* the
  /// reconnect flush has drained pending uploads/deletes, so the server reflects
  /// this device's edits before we pull:
  ///   • server row, no local row → insert as `.synced`.
  ///   • server row vs `.synced` local → server is authoritative; take its reading.
  ///   • server row vs `.local` (unsynced edit) → newer `updatedAt` wins; a local
  ///     win is left `.local` to upload on the next flush.
  ///   • server row vs `.pendingDelete` → keep the tombstone; the flush still owes
  ///     a `DELETE`, and resurrecting it would undo the user's deletion.
  ///   • `.synced` local row absent from the server → deleted on another device;
  ///     drop it. `.local` / `.pendingDelete` rows absent from the server are
  ///     mid-flight, not deletions, so they stay.
  func reconcileOverrides(userID: String, serverRows: [RemoteReadingOverride]) {
    let descriptor = FetchDescriptor<OverrideEntity>(
      predicate: #Predicate { $0.userID == userID }
    )
    let local = (try? context.fetch(descriptor)) ?? []
    let bySurface = Dictionary(
      local.map { ($0.surface, $0) },
      uniquingKeysWith: { current, _ in current }
    )
    var serverSurfaces: Set<String> = []

    for row in serverRows {
      serverSurfaces.insert(row.surface)
      guard let existing = bySurface[row.surface] else {
        context.insert(OverrideEntity(
          userID: userID,
          surface: row.surface,
          reading: row.reading,
          source: .synced,
          updatedAt: row.updatedAt
        ))
        continue
      }
      switch existing.source {
      case OverrideEntity.Source.pendingDelete.rawValue:
        continue // tombstone: the flush owes a DELETE; don't resurrect.
      case OverrideEntity.Source.local.rawValue:
        guard row.updatedAt > existing.updatedAt
        else { continue } // local edit is newer; keep it to upload.
        existing.reading = row.reading
        existing.updatedAt = row.updatedAt
        existing.source = OverrideEntity.Source.synced.rawValue
      default: // .synced — server is authoritative.
        existing.reading = row.reading
        existing.updatedAt = row.updatedAt
      }
    }

    for existing in local
      where !serverSurfaces.contains(existing.surface)
      && existing.source == OverrideEntity.Source.synced.rawValue
    {
      context.delete(existing)
    }
    try? context.save()
  }

  /// Promote a local override to `synced` after the server acknowledges its upload.
  func markOverrideSynced(userID: String, surface: String) {
    guard let existing = overrideRow(userID: userID, surface: surface) else { return }
    existing.source = OverrideEntity.Source.synced.rawValue
    try? context.save()
  }

  /// Overrides recorded on-device but not yet uploaded, for the next online tick
  /// to flush.
  func pendingOverrides(forUserID userID: String) -> [(surface: String, reading: String)] {
    let localSource = OverrideEntity.Source.local.rawValue
    let descriptor = FetchDescriptor<OverrideEntity>(
      predicate: #Predicate { $0.userID == userID && $0.source == localSource }
    )
    let rows = (try? context.fetch(descriptor)) ?? []
    return rows.map { ($0.surface, $0.reading) }
  }

  private func overrideRow(userID: String, surface: String) -> OverrideEntity? {
    var descriptor = FetchDescriptor<OverrideEntity>(
      predicate: #Predicate { $0.userID == userID && $0.surface == surface }
    )
    descriptor.fetchLimit = 1
    return try? context.fetch(descriptor).first
  }

  // MARK: Flashcards

  /// The full deck for a user as plain `Flashcard` values, newest first.
  /// `.pendingDelete` tombstones are excluded — they are on their way out.
  func flashcards(forUserID userID: String) -> [Flashcard] {
    let deleted = FlashcardEntity.Source.pendingDelete.rawValue
    let descriptor = FetchDescriptor<FlashcardEntity>(
      predicate: #Predicate { $0.userID == userID && $0.source != deleted },
      sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
    )
    let rows = (try? context.fetch(descriptor)) ?? []
    return rows.map(\.asFlashcard)
  }

  /// Cards whose `dueAt` is at or before `now`, oldest-due first — the study
  /// queue. Tombstones excluded.
  func dueFlashcards(forUserID userID: String, now: Date = .now) -> [Flashcard] {
    let deleted = FlashcardEntity.Source.pendingDelete.rawValue
    let descriptor = FetchDescriptor<FlashcardEntity>(
      predicate: #Predicate { $0.userID == userID && $0.source != deleted && $0.dueAt <= now },
      sortBy: [SortDescriptor(\.dueAt)]
    )
    let rows = (try? context.fetch(descriptor)) ?? []
    return rows.map(\.asFlashcard)
  }

  /// Surfaces of every card in the deck, for the lyric surface's "already saved"
  /// markers and the capture toggle. Tombstones excluded so a removed word's
  /// marker clears.
  func flashcardSurfaces(forUserID userID: String) -> Set<String> {
    let deleted = FlashcardEntity.Source.pendingDelete.rawValue
    let descriptor = FetchDescriptor<FlashcardEntity>(
      predicate: #Predicate { $0.userID == userID && $0.source != deleted }
    )
    let rows = (try? context.fetch(descriptor)) ?? []
    return Set(rows.map(\.surface))
  }

  /// Record (or update) a card locally. A capture / grade / gloss write passes
  /// `source = .local` so it reflects before any upload; a sync-down passes
  /// `.synced`. The whole card is written so a later upsert sends a complete row.
  func upsertFlashcard(userID: String, card: Flashcard, source: FlashcardEntity.Source) {
    if let existing = flashcardRow(userID: userID, surface: card.surface) {
      existing.reading = card.reading
      existing.meaningJson = encodeGlossMap(card.meaning)
      existing.sourceTitle = card.sourceTitle
      existing.sourceArtist = card.sourceArtist
      existing.sourceLine = card.sourceLine
      existing.sourceLineTranslationJson = encodeGlossMap(card.sourceLineTranslation)
      existing.sourceLineStartMs = card.sourceLineStartMs
      existing.sourceLineEndMs = card.sourceLineEndMs
      existing.sourceProvider = card.sourceProvider
      existing.sourceTrackID = card.sourceTrackID
      existing.level = card.level
      existing.dueAt = card.dueAt
      existing.source = source.rawValue
      existing.updatedAt = card.updatedAt
    } else {
      context.insert(FlashcardEntity(
        userID: userID,
        surface: card.surface,
        reading: card.reading,
        meaningJson: encodeGlossMap(card.meaning),
        sourceTitle: card.sourceTitle,
        sourceArtist: card.sourceArtist,
        sourceLine: card.sourceLine,
        sourceLineTranslationJson: encodeGlossMap(card.sourceLineTranslation),
        sourceLineStartMs: card.sourceLineStartMs,
        sourceLineEndMs: card.sourceLineEndMs,
        sourceProvider: card.sourceProvider,
        sourceTrackID: card.sourceTrackID,
        level: card.level,
        dueAt: card.dueAt,
        source: source,
        updatedAt: card.updatedAt,
        createdAt: card.createdAt
      ))
    }
    try? context.save()
  }

  /// Remove a card the user deleted. A never-uploaded `.local` row is dropped
  /// outright; a `.synced` row is tombstoned so a later server pull can't
  /// resurrect it (the flush issues the `DELETE`, then calls `removeFlashcard`).
  func deleteFlashcard(userID: String, surface: String) {
    guard let existing = flashcardRow(userID: userID, surface: surface) else { return }
    if existing.source == FlashcardEntity.Source.local.rawValue {
      context.delete(existing)
    } else {
      existing.source = FlashcardEntity.Source.pendingDelete.rawValue
    }
    try? context.save()
  }

  /// Hard-remove a card row with no tombstone, after a server `DELETE` succeeds.
  func removeFlashcard(userID: String, surface: String) {
    guard let existing = flashcardRow(userID: userID, surface: surface) else { return }
    context.delete(existing)
    try? context.save()
  }

  /// Promote a local card to `synced` after the server acknowledges its upload.
  func markFlashcardSynced(userID: String, surface: String) {
    guard let existing = flashcardRow(userID: userID, surface: surface) else { return }
    existing.source = FlashcardEntity.Source.synced.rawValue
    try? context.save()
  }

  /// Cards written on-device but not yet uploaded, for the reconnect flush to
  /// upsert. Each is a full card so the upload sends a complete row.
  func pendingFlashcards(forUserID userID: String) -> [Flashcard] {
    let local = FlashcardEntity.Source.local.rawValue
    let descriptor = FetchDescriptor<FlashcardEntity>(
      predicate: #Predicate { $0.userID == userID && $0.source == local }
    )
    let rows = (try? context.fetch(descriptor)) ?? []
    return rows.map(\.asFlashcard)
  }

  /// Surfaces of cards tombstoned for deletion, for the flush to drain as `DELETE`s.
  func pendingFlashcardDeletes(forUserID userID: String) -> [String] {
    let deleted = FlashcardEntity.Source.pendingDelete.rawValue
    let descriptor = FetchDescriptor<FlashcardEntity>(
      predicate: #Predicate { $0.userID == userID && $0.source == deleted }
    )
    let rows = (try? context.fetch(descriptor)) ?? []
    return rows.map(\.surface)
  }

  /// Reconcile the local deck with the server's `flashcards` rows, last-writer-wins
  /// by `updatedAt` — the same discipline as `reconcileOverrides`. Run *after* the
  /// flush has drained pending uploads/deletes:
  ///   • server row, no local row → insert as `.synced`.
  ///   • server row vs `.synced` local → server is authoritative.
  ///   • server row vs `.local` (unsynced) → newer `updatedAt` wins; a local win
  ///     stays `.local` to upload next flush.
  ///   • server row vs `.pendingDelete` → keep the tombstone (a `DELETE` is owed).
  ///   • `.synced` local absent from server → deleted elsewhere; drop it. `.local`
  ///     / `.pendingDelete` absent are mid-flight, so they stay.
  func reconcileFlashcards(userID: String, serverRows: [Flashcard]) {
    let descriptor = FetchDescriptor<FlashcardEntity>(predicate: #Predicate { $0.userID == userID })
    let local = (try? context.fetch(descriptor)) ?? []
    let bySurface = Dictionary(
      local.map { ($0.surface, $0) },
      uniquingKeysWith: { current, _ in current }
    )
    var serverSurfaces: Set<String> = []

    for row in serverRows {
      serverSurfaces.insert(row.surface)
      guard let existing = bySurface[row.surface] else {
        context.insert(FlashcardEntity(
          userID: userID,
          surface: row.surface,
          reading: row.reading,
          meaningJson: encodeGlossMap(row.meaning),
          sourceTitle: row.sourceTitle,
          sourceArtist: row.sourceArtist,
          sourceLine: row.sourceLine,
          sourceLineTranslationJson: encodeGlossMap(row.sourceLineTranslation),
          sourceLineStartMs: row.sourceLineStartMs,
          sourceLineEndMs: row.sourceLineEndMs,
          sourceProvider: row.sourceProvider,
          sourceTrackID: row.sourceTrackID,
          level: row.level,
          dueAt: row.dueAt,
          source: .synced,
          updatedAt: row.updatedAt,
          createdAt: row.createdAt
        ))
        continue
      }
      switch existing.source {
      case FlashcardEntity.Source.pendingDelete.rawValue:
        continue // tombstone: a DELETE is owed; don't resurrect.
      case FlashcardEntity.Source.local.rawValue:
        guard row.updatedAt > existing.updatedAt
        else { continue } // local edit newer; keep to upload.
        applyServer(row, to: existing, source: .synced)
      default: // .synced — server authoritative.
        applyServer(row, to: existing, source: .synced)
      }
    }

    for existing in local
      where !serverSurfaces.contains(existing.surface)
      && existing.source == FlashcardEntity.Source.synced.rawValue
    {
      context.delete(existing)
    }
    try? context.save()
  }

  private func applyServer(
    _ row: Flashcard,
    to existing: FlashcardEntity,
    source: FlashcardEntity.Source
  ) {
    existing.reading = row.reading
    existing.meaningJson = encodeGlossMap(row.meaning)
    existing.sourceTitle = row.sourceTitle
    existing.sourceArtist = row.sourceArtist
    existing.sourceLine = row.sourceLine
    existing.sourceLineTranslationJson = encodeGlossMap(row.sourceLineTranslation)
    existing.sourceLineStartMs = row.sourceLineStartMs
    existing.sourceLineEndMs = row.sourceLineEndMs
    existing.sourceProvider = row.sourceProvider
    existing.sourceTrackID = row.sourceTrackID
    existing.level = row.level
    existing.dueAt = row.dueAt
    existing.updatedAt = row.updatedAt
    existing.source = source.rawValue
  }

  private func flashcardRow(userID: String, surface: String) -> FlashcardEntity? {
    var descriptor = FetchDescriptor<FlashcardEntity>(
      predicate: #Predicate { $0.userID == userID && $0.surface == surface }
    )
    descriptor.fetchLimit = 1
    return try? context.fetch(descriptor).first
  }

  // MARK: Maintenance

  /// 30-day staleness check against an entry's fetch/generate timestamp.
  func isStale(_ timestamp: Date, now: Date = .now) -> Bool {
    now.timeIntervalSince(timestamp) > Self.ttl
  }

  /// Evict cache entries older than the 90-day retention bound. Runs in a
  /// background launch phase so it never blocks first paint.
  func runJanitor(now: Date = .now) {
    let cutoff = now.addingTimeInterval(-Self.maxAge)
    try? context.delete(model: LyricBodyEntity.self, where: #Predicate { $0.fetchedAt < cutoff })
    try? context.delete(
      model: TranslationEntity.self,
      where: #Predicate { $0.generatedAt < cutoff }
    )
    try? context.save()
  }

  /// Purge every per-user entity on explicit sign-out. Device-local preferences
  /// (theme, language) live in `UserDefaults` and are untouched. Independent
  /// per-device auth means one user occupies the store at a time, so a full wipe
  /// is the user's scope.
  func purgeAll() {
    try? context.delete(model: SongEntity.self)
    try? context.delete(model: LyricBodyEntity.self)
    try? context.delete(model: OverrideEntity.self)
    try? context.delete(model: TranslationEntity.self)
    try? context.delete(model: FlashcardEntity.self)
    try? context.save()
  }
}
