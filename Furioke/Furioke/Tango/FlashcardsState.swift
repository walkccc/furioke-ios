import Foundation
import Observation
import SwiftUI

/// Backs the 単語 tab's study deck and browse list: reads the signed-in user's
/// cards from the cache and drives capture / grade / delete / gloss-fetch with the
/// same optimistic-local-then-upload discipline as `ReadingOverridesState`. The
/// reconnect flush (`flushPending`) is drained from the app's single reconnect
/// seam, `NowPlayingState.syncPendingOverrides`, so this state stays self-contained.
@Observable
@MainActor
final class FlashcardsState {
  /// The full deck, newest first, rebuilt by `reload`. `.pendingDelete` tombstones
  /// are already excluded by the cache accessor.
  private(set) var deck: [Flashcard] = []
  /// Surfaces of every saved card, for the lyric surface's "already saved" markers
  /// and the capture toggle. Rebuilt alongside `deck`.
  private(set) var savedSurfaces: Set<String> = []

  /// Surfaces with a gloss fetch in flight right now, so the deck row and study
  /// back face can show a translation placeholder while one lands. Keyed by
  /// `surface` (the card identity), so a card glossing in study and browse at once
  /// reads as one in-flight state.
  private(set) var glossingSurfaces: Set<String> = []

  private let cache: OfflineCache
  private let service: FlashcardsService
  private let auth: AuthService
  private let network: NetworkMonitor
  private let preferences: PreferencesState
  private let translation: TranslationService
  private let quota: QuotaNotice

  init(
    cache: OfflineCache,
    service: FlashcardsService,
    auth: AuthService,
    network: NetworkMonitor,
    preferences: PreferencesState,
    translation: TranslationService,
    quota: QuotaNotice
  ) {
    self.cache = cache
    self.service = service
    self.auth = auth
    self.network = network
    self.preferences = preferences
    self.translation = translation
    self.quota = quota
  }

  /// Whether the active language's gloss for `surface` is being fetched right now —
  /// drives the translation placeholder in the deck list and the study back face.
  func isGlossing(_ surface: String) -> Bool {
    glossingSurfaces.contains(surface)
  }

  /// Flashcards are per-user, so a signed-out visitor sees a sign-in prompt.
  var isSignedIn: Bool {
    currentUserID != nil
  }

  /// The cards due now, oldest-due first — the study queue seed.
  var dueCards: [Flashcard] {
    guard let userID = currentUserID else { return [] }
    return applyingOverrides(cache.dueFlashcards(forUserID: userID), userID: userID)
  }

  func isSaved(_ surface: String) -> Bool {
    savedSurfaces.contains(surface)
  }

  /// Rebuild the deck + saved set from the cache. Called on appear and after every
  /// mutation.
  func reload() {
    guard let userID = currentUserID else {
      deck = []
      savedSurfaces = []
      return
    }
    deck = applyingOverrides(cache.flashcards(forUserID: userID), userID: userID)
    savedSurfaces = cache.flashcardSurfaces(forUserID: userID)
  }

  /// Fold the learner's reading overrides over a batch of cards: a word the learner
  /// corrected in Now Playing (keyed by `surface`) renders with the corrected
  /// reading here too, so the deck's furigana stays consistent with the lyric
  /// surface. The stored card is untouched — this is a display-time overlay only.
  private func applyingOverrides(_ cards: [Flashcard], userID: String) -> [Flashcard] {
    let overrides = cache.overrides(forUserID: userID)
    guard !overrides.isEmpty else { return cards }
    return cards.map { card in
      guard let reading = overrides[card.surface], reading != card.reading else { return card }
      return card.withReading(reading)
    }
  }

  /// Pull the server's deck into the cache, then reload. Mirrors
  /// `ReadingOverridesState.sync`: no-op offline (the deck renders from the cache
  /// and must not blank). The queued-write flush is owned by `flushPending`.
  func sync() async {
    guard network.isOnline, let userID = currentUserID else { return }
    guard let serverRows = try? await service.fetchAll() else { return }
    cache.reconcileFlashcards(userID: userID, serverRows: serverRows)
    reload()
  }

  // MARK: Capture

  /// Capture toggle from the lyric surface: save the word if it isn't in the deck,
  /// remove it if it is. Idempotent per surface.
  func toggleSave(_ input: SaveFlashcardInput) async {
    if isSaved(input.surface) {
      await remove(surface: input.surface)
    } else {
      await save(input)
    }
  }

  /// Save a captured word: optimistic local write first (so the marker and deck
  /// reflect it at once), then upload when online; a failed upload stays `.local`
  /// for the reconnect flush.
  func save(_ input: SaveFlashcardInput) async {
    guard let userID = currentUserID else { return }
    let now = Date()
    let card = Flashcard(
      surface: input.surface,
      reading: input.reading,
      sourceTitle: input.sourceTitle,
      sourceArtist: input.sourceArtist,
      sourceLine: input.sourceLine,
      sourceLineStartMs: input.sourceLineStartMs,
      sourceLineEndMs: input.sourceLineEndMs,
      sourceProvider: input.sourceProvider,
      sourceTrackID: input.sourceTrackID,
      level: 0,
      dueAt: now,
      createdAt: now,
      updatedAt: now
    )
    cache.upsertFlashcard(userID: userID, card: card, source: .local)
    reload()
    await upload(card, userID: userID)
  }

  /// Remove a card. Online + already synced: issue the `DELETE`, then drop the row
  /// (tombstone on failure). Otherwise (`.local` never-uploaded, or synced-offline)
  /// hand off to the cache, which drops a `.local` row and tombstones a `.synced`.
  func remove(surface: String) async {
    guard let userID = currentUserID else { return }
    let isPending = deck.first { $0.surface == surface }?.isPendingSync ?? false
    if !isPending, network.isOnline {
      do {
        try await service.delete(surface: surface)
        cache.removeFlashcard(userID: userID, surface: surface)
      } catch {
        cache.deleteFlashcard(userID: userID, surface: surface)
      }
    } else {
      cache.deleteFlashcard(userID: userID, surface: surface)
    }
    reload()
  }

  // MARK: Study

  /// Grade a card: advance the Leitner schedule locally, then upload. A grade is
  /// persisted through the same optimistic path as a save, so it survives offline.
  func grade(_ card: Flashcard, _ grade: FlashcardGrade) async {
    guard let userID = currentUserID else { return }
    let updated = FlashcardSchedule.grade(card, grade)
    cache.upsertFlashcard(userID: userID, card: updated, source: .local)
    reload()
    await upload(updated, userID: userID)
  }

  // MARK: Glosses

  /// Fetch the active language's meaning and source-line translation for a card if
  /// they're missing, persist them, and return the updated card. One language is
  /// fetched at a time; already-present glosses and other languages are untouched.
  /// While a fetch is in flight the card's surface is in `glossingSurfaces` so the
  /// UI can show a placeholder. Offline / provider failures are non-fatal — the
  /// original card is returned so the back face still shows word + reading + lyric;
  /// a 429 (the per-user daily quota, the dominant failure) raises the shared
  /// out-of-quota notice — but only when `raisesQuotaNotice` is set, so the toast
  /// fires from an explicit tap-to-translate and never from the study deck's silent
  /// on-flip prefetch. Mirrors the web's lazy gloss fetch.
  @discardableResult
  func glossed(_ card: Flashcard, raisesQuotaNotice: Bool = true) async -> Flashcard {
    guard let userID = currentUserID, network.isOnline else { return card }
    let target = preferences.translationTarget
    let needsMeaning = glossFor(card.meaning, target) == nil
    let needsLine = card.sourceLine != nil && glossFor(card.sourceLineTranslation, target) == nil
    guard needsMeaning || needsLine else { return card }

    glossingSurfaces.insert(card.surface)
    defer { glossingSurfaces.remove(card.surface) }

    var card = card
    var changed = false
    do {
      if needsMeaning,
         let meaning = try await translation.glossary(word: card.surface, target: target),
         !meaning.isEmpty
      {
        card.meaning[target] = meaning
        changed = true
      }
      if needsLine, let line = card.sourceLine {
        let plain = SourceLineCodec.plainText(line)
        if let translated = try await translation.translate(text: plain, target: target),
           !translated.isEmpty
        {
          card.sourceLineTranslation[target] = translated
          changed = true
        }
      }
    } catch TranslationService.TranslationError.requestFailed(429) {
      // Out of daily translations: surface the shared upgrade notice — but only for
      // an explicit tap. A silent prefetch passes `raisesQuotaNotice: false`, so
      // merely advancing the study deck never fires the toast. Anything fetched
      // before the limit was hit is still persisted below.
      if raisesQuotaNotice { quota.translationLimitReached() }
    } catch {
      // Offline / provider / auth: degrade quietly — the card keeps word + reading
      // + lyric, and the next appearance retries.
    }

    guard changed else { return card }
    card.updatedAt = Date()
    cache.upsertFlashcard(userID: userID, card: card, source: .local)
    reload()
    await upload(card, userID: userID)
    return card
  }

  // MARK: Sync

  /// Flush queued card writes for the signed-in user, then pull the server's rows.
  /// Order matches `syncPendingOverrides`: uploads (`.local`) and deletions
  /// (`.pendingDelete`) go up first so the server reflects this device's edits,
  /// then `reconcileFlashcards` pulls last-writer-wins. Drained from the app's
  /// single reconnect seam.
  func flushPending() async {
    guard network.isOnline, let userID = currentUserID else { return }
    for card in cache.pendingFlashcards(forUserID: userID) {
      await upload(card, userID: userID, reload: false)
    }
    for surface in cache.pendingFlashcardDeletes(forUserID: userID) {
      do {
        try await service.delete(surface: surface)
        cache.removeFlashcard(userID: userID, surface: surface)
      } catch {
        // Stay tombstoned; the next reconnect retries the DELETE.
      }
    }
    await sync()
  }

  /// Upload one card and promote it to `synced` on success; leave it `.local`
  /// (queued) on failure or while offline for the next flush.
  private func upload(_ card: Flashcard, userID: String, reload: Bool = true) async {
    guard network.isOnline else { return }
    do {
      try await service.upsert(card)
      cache.markFlashcardSynced(userID: userID, surface: card.surface)
      if reload { self.reload() }
    } catch {
      // Stay local; the reconnect flush retries the upload.
    }
  }

  /// The signed-in user's id in the lowercased-UUID form used for `FlashcardEntity`
  /// rows and the `flashcards.user_id` column; nil when signed out. Mirrors
  /// `NowPlayingState.currentUserID`.
  private var currentUserID: String? {
    if case let .signedIn(userID) = auth.state {
      return userID.uuidString.lowercased()
    }
    return nil
  }
}
