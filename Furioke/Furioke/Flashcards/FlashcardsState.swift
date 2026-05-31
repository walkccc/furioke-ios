import Foundation
import Observation

/// The flashcards slice observable: the seam the reading editor uses to save a
/// word, the lyric surface uses for its saved markers, and the deck / study views
/// read. It follows `LibraryState` (a server-backed collection mirrored in
/// SwiftData) plus `NowPlayingState`'s override-sync shape: optimistic local
/// writes, an offline queue, and a reconnect flush that reconciles
/// last-writer-wins by `updatedAt`.
///
/// The cache is the single source of truth; every write goes through it and then
/// `reload()` refreshes the in-memory `cards` / `savedSurfaces` the views bind
/// to. Reads happen straight from the local mirror so the deck renders offline.
@Observable
@MainActor
final class FlashcardsState {
  /// The deck, most-recently-updated first. Views bind to this directly.
  private(set) var cards: [Flashcard] = []
  /// Surfaces in the deck, mirrored for O(1) saved-marker / capture-toggle checks.
  private(set) var savedSurfaces: Set<String> = []

  private let cache: OfflineCache
  private let service: FlashcardsService
  private let auth: AuthService
  private let network: NetworkMonitor
  private let translation: TranslationService
  private let preferences: PreferencesState

  /// Per-surface guard so a card's on-demand context is fetched once at a time.
  @ObservationIgnored private var contextInFlight: Set<String> = []

  init(
    cache: OfflineCache,
    service: FlashcardsService,
    auth: AuthService,
    network: NetworkMonitor,
    translation: TranslationService,
    preferences: PreferencesState
  ) {
    self.cache = cache
    self.service = service
    self.auth = auth
    self.network = network
    self.translation = translation
    self.preferences = preferences
    reload()
    observeReconnect()
    observeAuth()
  }

  func isSaved(_ surface: String) -> Bool {
    savedSurfaces.contains(surface)
  }

  /// Cards whose `dueAt` is at or before `now`, for study mode.
  func dueCards(now: Date = .now) -> [Flashcard] {
    cards.filter { FlashcardSchedule.isDue($0, now: now) }
  }

  // MARK: Capture / mutate

  /// Toggle a word's deck membership: save it if absent, remove it if present
  /// (the lyric editor's single affordance). Idempotent — re-saving an existing
  /// surface removes it rather than duplicating.
  func toggleSave(_ input: SaveFlashcardInput) {
    guard let userID = currentUserID else { return }
    if savedSurfaces.contains(input.surface) {
      remove(surface: input.surface)
      return
    }
    let now = Date.now
    let card = Flashcard(
      surface: input.surface,
      reading: input.reading,
      meaning: [:],
      sourceTitle: input.sourceTitle,
      sourceArtist: input.sourceArtist,
      sourceLine: input.sourceLine,
      sourceLineTranslation: [:],
      level: 0,
      dueAt: now,
      createdAt: now,
      updatedAt: now
    )
    cache.upsertFlashcard(userID: userID, card: card, source: .local)
    reload()
    Task { await pushUpsert(userID: userID, surface: card.surface) }
  }

  func remove(surface: String) {
    guard let userID = currentUserID else { return }
    cache.deleteFlashcard(userID: userID, surface: surface)
    reload()
    Task { await pushDelete(userID: userID, surface: surface) }
  }

  /// Grade a card in study mode through the shared scheduler, then persist via
  /// the same offline-capable write path as a save — so grading works offline.
  func grade(surface: String, _ grade: FlashcardGrade, now: Date = .now) {
    guard let userID = currentUserID,
          let card = cards.first(where: { $0.surface == surface }) else { return }
    let next = FlashcardSchedule.grade(card, grade, now: now)
    cache.upsertFlashcard(userID: userID, card: next, source: .local)
    reload()
    Task { await pushUpsert(userID: userID, surface: surface) }
  }

  /// Fill whatever a card is missing — `meaning` and/or `sourceLineTranslation` —
  /// in one combined vocab translation call, then persist the patch. Mirrors the
  /// web's `fetchCardContext`. Failures (offline, quota, network) are non-fatal:
  /// the card stays usable, just without the gloss.
  func fetchCardContext(surface: String) async {
    guard let userID = currentUserID,
          let card = cards.first(where: { $0.surface == surface }) else { return }

    // Glosses are per language: fetch only the active language's missing keys,
    // leaving any other languages already stored on the card untouched.
    let target = preferences.language.translationTarget
    var requests: [(meaning: Bool, text: String)] = []
    if card.meaning(for: target) == nil {
      requests.append((true, surface))
    }
    let plainLine = card.sourceLine
      .map(SourceLineCodec.stripAnnotations)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !plainLine.isEmpty, card.sourceLineTranslation(for: target) == nil {
      requests.append((false, plainLine))
    }
    // Guard per (surface, language) so switching language can still fetch the
    // newly active language's gloss while another is in flight.
    let inFlightKey = "\(target):\(surface)"
    guard !requests.isEmpty, !contextInFlight.contains(inFlightKey) else { return }

    contextInFlight.insert(inFlightKey)
    defer { contextInFlight.remove(inFlightKey) }

    guard let lines = try? await translation.translateVocab(
      lines: requests.map(\.text), target: target
    ), lines.count == requests.count else { return }

    var next = card
    for (index, request) in requests.enumerated() {
      let value = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
      guard !value.isEmpty else { continue }
      if request.meaning {
        next.meaning[target] = value
      } else {
        next.sourceLineTranslation[target] = value
      }
    }
    guard next != card else { return }
    // Re-read the live card: the deck may have changed while the request was in
    // flight. Skip if the card was removed.
    guard cache.flashcard(userID: userID, surface: surface) != nil else { return }
    cache.upsertFlashcard(userID: userID, card: next, source: .local)
    reload()
    Task { await pushUpsert(userID: userID, surface: surface) }
  }

  // MARK: Sync

  func sync() async {
    await syncPendingFlashcards()
  }

  /// Flush queued writes, then pull and reconcile — order matters so the server
  /// reflects this device's edits before the pull (mirrors `syncPendingOverrides`).
  func syncPendingFlashcards() async {
    guard network.isOnline, let userID = currentUserID else { return }
    for card in cache.pendingFlashcardUpserts(forUserID: userID) {
      do {
        try await service.upsert(card)
        cache.markFlashcardSynced(userID: userID, surface: card.surface)
      } catch {
        // Stay local; a later flush retries.
      }
    }
    for surface in cache.pendingFlashcardDeletes(forUserID: userID) {
      do {
        try await service.delete(surface: surface)
        cache.removeFlashcard(userID: userID, surface: surface)
      } catch {
        // Stay tombstoned; the next reconnect retries the DELETE.
      }
    }
    guard let serverCards = try? await service.fetchAll() else {
      reload()
      return
    }
    cache.reconcileFlashcards(userID: userID, serverCards: serverCards)
    reload()
  }

  // MARK: Internals

  private func reload() {
    guard let userID = currentUserID else {
      cards = []
      savedSurfaces = []
      return
    }
    cards = cache.flashcards(forUserID: userID)
    savedSurfaces = cache.savedFlashcardSurfaces(forUserID: userID)
  }

  /// Push one locally-written card; leaves it `.local` (queued) on failure or
  /// while offline for the next flush.
  private func pushUpsert(userID: String, surface: String) async {
    guard network.isOnline, let card = cache.flashcard(userID: userID, surface: surface) else { return }
    do {
      try await service.upsert(card)
      cache.markFlashcardSynced(userID: userID, surface: surface)
    } catch {
      // Stay local; `observeReconnect` / a later write will retry.
    }
  }

  private func pushDelete(userID: String, surface: String) async {
    guard network.isOnline else { return }
    do {
      try await service.delete(surface: surface)
      cache.removeFlashcard(userID: userID, surface: surface)
    } catch {
      // Stay tombstoned for the reconnect flush.
    }
  }

  /// The signed-in user's id in the lowercased-UUID form used for the
  /// `FlashcardEntity.userID` column; nil when signed out.
  private var currentUserID: String? {
    if case let .signedIn(userID) = auth.state {
      return userID.uuidString.lowercased()
    }
    return nil
  }

  /// Flush queued writes whenever the device returns online. Re-arms after each
  /// change because `withObservationTracking` fires once per registration.
  private func observeReconnect() {
    withObservationTracking {
      _ = network.isOnline
    } onChange: {
      Task { @MainActor [weak self] in
        guard let self else { return }
        if self.network.isOnline { await self.syncPendingFlashcards() }
        self.observeReconnect()
      }
    }
  }

  /// Re-seed (and clear on sign-out) when the session changes, so a new account
  /// never inherits the previous user's in-memory deck and a fresh sign-in pulls
  /// its own. The cache is purged separately by `auth.onSignOutCleanup`.
  private func observeAuth() {
    withObservationTracking {
      _ = auth.state
    } onChange: {
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.reload()
        await self.syncPendingFlashcards()
        self.observeAuth()
      }
    }
  }
}
