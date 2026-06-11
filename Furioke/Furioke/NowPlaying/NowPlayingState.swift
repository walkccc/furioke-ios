import Foundation
import Observation
import SwiftUI

/// A reading edit in progress, driving the focus-overlay editor
/// (`ReadingEditorCard`). `surface` is the kanji being corrected — it doubles as
/// the override key — `reading` is the editable draft, and `rememberEverywhere`
/// mirrors the **Remember this reading** toggle (persist as a personal override
/// vs. session-only). Starts off (session-only); the editor auto-arms it when the
/// reading is actually edited.
struct ReadingEdit: Equatable {
  let surface: String
  var reading: String
  var rememberEverywhere: Bool
  /// The lyric line the word was long-pressed in, pipe-encoded
  /// (`SourceLineCodec`), so a flashcard captured from this editor keeps its
  /// source context. Nil when the line is unknown.
  var sourceLine: String?
  /// The long-pressed line's start time (ms) for synced lyrics, so a captured
  /// flashcard can later seek the player to it. Nil for plain (un-timed) lyrics
  /// or an unknown line.
  var sourceLineStartMs: Int?
  /// The next timed line's start (ms) — the long-pressed line's end — so a
  /// captured flashcard can play just that line. Nil for the last line or plain
  /// lyrics.
  var sourceLineEndMs: Int?
}

/// Owns the NowPlaying lyric surface and the single seam from Library / Search
/// into playback. `play(track:)` is the only entry point that starts a track:
/// it marks the source user-initiated, presents the NowPlaying surface, drives the
/// active adapter, and kicks off the lyric load **without waiting** for the SDK to
/// echo the track back.
@Observable
@MainActor
final class NowPlayingState {
  enum LyricsStatus: Equatable {
    case idle
    case loading
    case loaded
    case notFound
    case unavailableOffline
    case failed
  }

  enum TranslationStatus: Equatable {
    case idle
    case loading
    case loaded
    /// Online attempt failed with nothing cached. The dominant cause is the
    /// per-user daily quota (the route returns 429 at-limit), so its notice leads
    /// with the limit; provider/not-found failures share the same copy.
    case unavailable
    /// Offline with nothing cached.
    case unavailableOffline
  }

  private(set) var status: LyricsStatus = .idle
  private(set) var lines: [AnnotatedLine] = []

  /// True while the raw lyrics are already on screen but furigana is still being
  /// computed (the kuromoji tokenizer's cold build can take several seconds).
  /// Drives the "adding furigana" indicator; the lines upgrade in place when done.
  private(set) var furiganaLoading = false

  private(set) var translationStatus: TranslationStatus = .idle
  /// Translated lines aligned by index to `lines`; empty entries render nothing.
  private(set) var translatedLines: [String] = []

  /// Reading-display preferences for the lyric surface, toggled from the
  /// NowPlaying top bar. Furigana is on by default (the app's reason to exist);
  /// rōmaji and translation are opt-in. In-memory only — they reset per launch.
  var showFurigana = true
  var showRomaji = false
  private(set) var showTranslation = false

  /// Whether the NowPlaying surface is presented. Drives the `.fullScreenCover`
  /// (and its zoom transition) in `AppShell`; the system writes `false` back here
  /// on interactive swipe-to-dismiss. `play(track:)` sets it to open.
  var isPresented = false

  /// The reading edit currently open in the focus-overlay editor, or nil when the
  /// editor is closed. Set by a long-press on a kanji token; cleared on cancel,
  /// commit, or a track change.
  var editingReading: ReadingEdit?

  private let music: MusicState
  private let repository: LyricRepository
  private let translation: TranslationRepository
  private let preferences: PreferencesState
  private let cache: OfflineCache
  private let auth: AuthService
  private let corrections: ReadingCorrectionsService
  private let flashcards: FlashcardsState
  private let network: NetworkMonitor
  private let ratingPrompt: RatingPromptController
  private let annotator = FuriganaAnnotator()

  @ObservationIgnored private var loadTask: Task<Void, Never>?
  @ObservationIgnored private var translationTask: Task<Void, Never>?
  @ObservationIgnored private var noticeResetTask: Task<Void, Never>?
  @ObservationIgnored private var reannotateTask: Task<Void, Never>?
  @ObservationIgnored private var loadedTrackID: String?

  /// The last track whose successful lyric load was already counted toward the
  /// review prompt, so the cache emitting twice (cached then revalidated body) for
  /// one track counts as a single song view.
  @ObservationIgnored private var ratedTrackID: String?

  /// The raw LRC body for the loaded track, kept so a reading edit can re-run the
  /// furigana annotator locally without re-fetching `/api/lyrics`.
  @ObservationIgnored private var loadedBody: String?

  /// In-session, non-persisted overrides from an **Apply to all songs**-off edit:
  /// they rewrite the current rendering only and are dropped when the track
  /// changes. Persisted overrides live in `OverrideEntity`.
  @ObservationIgnored private var sessionOverrides: [String: String] = [:]

  init(
    music: MusicState,
    repository: LyricRepository,
    translation: TranslationRepository,
    preferences: PreferencesState,
    cache: OfflineCache,
    auth: AuthService,
    corrections: ReadingCorrectionsService,
    flashcards: FlashcardsState,
    network: NetworkMonitor,
    ratingPrompt: RatingPromptController
  ) {
    self.music = music
    self.repository = repository
    self.translation = translation
    self.preferences = preferences
    self.cache = cache
    self.auth = auth
    self.corrections = corrections
    self.flashcards = flashcards
    self.network = network
    self.ratingPrompt = ratingPrompt
    observeCurrentTrack()
    observeReconnect()
    observeLanguage()
  }

  /// Whether a whole-body translation request is in flight, for the progress
  /// toast. Distinct from `translationNoticeText`, which surfaces only the
  /// failed/unavailable outcomes (the two are mutually exclusive states).
  var isTranslating: Bool {
    translationStatus == .loading
  }

  /// A transient banner for a failed/unavailable translation attempt; nil when
  /// there's nothing to surface. Cleared automatically a few seconds after it's set.
  var translationNoticeText: LocalizedStringKey? {
    switch translationStatus {
    case .unavailableOffline: "Translation isn't available offline."
    case .unavailable:
      "You've reached today's limit of \(TranslationService.dailyLimit) translations. Try again tomorrow."
    case .idle, .loading, .loaded: nil
    }
  }

  /// Start a user-picked track and present the NowPlaying surface. Library and
  /// Search call this instead of switching tabs.
  func play(track: MusicTrack) {
    // Show the tapped track's metadata + artwork at once, before the adapter
    // echoes it back (which for a disconnected Spotify is a connect round-trip).
    music.showUserInitiated(track)
    present()
    // Drive the adapter, but do not block the lyric load on its echo.
    Task { _ = await music.playTrack(track) }
    loadLyrics(for: track)
  }

  /// Present / dismiss the NowPlaying surface with the snappy `Motion.sheet`
  /// curve, so the zoom transition settles fast and its swipe-to-dismiss arms
  /// promptly. The system also writes `isPresented = false` directly on an
  /// interactive swipe — that path bypasses these and animates itself.
  func present() {
    withAnimation(Motion.sheet) { isPresented = true }
  }

  func dismiss() {
    withAnimation(Motion.sheet) { isPresented = false }
  }

  /// Mirror the active provider's published track into the lyric surface. This
  /// covers playback the app did not initiate — most importantly the connect
  /// flow, where `authorizeAndPlayURI("")` resumes the user's last Spotify
  /// context and the track arrives only via the SDK echo (the companion path).
  /// `play(track:)` already loads lyrics synchronously
  /// for the user-initiated path; the `loadedTrackID` guard makes this a no-op
  /// when the echo repeats that same track. Re-arms after each change because
  /// `withObservationTracking` fires its handler once per registration.
  private func observeCurrentTrack() {
    withObservationTracking {
      _ = music.currentTrack
    } onChange: {
      Task { @MainActor [weak self] in
        guard let self else { return }
        handleCurrentTrackChange()
        observeCurrentTrack()
      }
    }
  }

  private func handleCurrentTrackChange() {
    guard let track = music.currentTrack else {
      loadTask?.cancel()
      loadedTrackID = nil
      status = .idle
      lines = []
      return
    }
    loadLyrics(for: track)
  }

  /// Load the lyric body through the offline read-through cache and run each
  /// emitted body through the local furigana annotator. The cache may emit twice on
  /// the online-fresh path (cached body, then a revalidated body), so the stream
  /// is consumed to completion and the surface re-renders on each `.value`. Guarded
  /// so re-entry for the same track is a no-op.
  func loadLyrics(for track: MusicTrack) {
    guard loadedTrackID != track.id else { return }
    loadedTrackID = track.id

    loadTask?.cancel()
    translationTask?.cancel()
    reannotateTask?.cancel()
    status = .loading
    lines = []
    furiganaLoading = false
    // A new track drops the previous body and any session-only reading edits, so
    // an **Apply to all songs**-off correction reverts on the next track.
    // Persisted overrides still apply via the cache.
    loadedBody = nil
    sessionOverrides = [:]
    // A new track closes any open reading editor — its target word no longer
    // exists in the surface.
    editingReading = nil
    // A new track invalidates any translation; re-fetch lazily if the toggle is on
    // once the new lyrics land.
    translatedLines = []
    translationStatus = .idle

    loadTask = Task { [weak self] in
      guard let self else { return }
      for await event in repository.load(for: track) {
        if Task.isCancelled { return }
        apply(event)
      }
    }
  }

  /// Render one read-through outcome: tokenize a body, or surface the matching
  /// not-found / offline-unavailable / failed state.
  private func apply(_ event: CacheLoad<LyricFetchResult>) {
    switch event {
    case let .value(result):
      loadedBody = result.body
      // Show the raw lyrics immediately so the surface is readable at once, then
      // compute furigana in the background and upgrade the lines in place. The
      // kuromoji tokenizer's first (cold) build can take several seconds, and
      // blocking the whole surface on it is what made lyrics feel slow to load.
      lines = annotator.plainLines(lrcBody: result.body)
      status = .loaded
      // Lyrics on screen is the app's core value moment — count it toward the
      // review prompt, once per track (the cache can emit a cached then a
      // revalidated body for the same song).
      if ratedTrackID != loadedTrackID {
        ratedTrackID = loadedTrackID
        ratingPrompt.recordSongViewed()
      }
      // Funnel the initial pass through the same cancellable task as a later
      // override change: if the launch override sync lands while this (cold, slow)
      // tokenize is in flight, its `reannotate` cancels this pass and re-runs with
      // the freshly-synced corrections — so a stale map can't finish late and
      // clobber the override-applied lines.
      reannotate(showingLoadingIndicator: true, reloadsTranslation: true)
    case .notFound:
      status = .notFound
    case .unavailableOffline:
      status = .unavailableOffline
    case .failed:
      status = .failed
    }
  }

  // MARK: Reading corrections

  /// Open the focus-overlay reading editor for a long-pressed kanji token. The
  /// draft starts from the token's current reading. The **Remember this reading**
  /// toggle opens armed (shown + checked) when the word already carries a persisted
  /// override — its displayed reading *is* that override — and otherwise off, so an
  /// untouched Save stays session-only and `ReadingEditorCard` auto-arms it once the
  /// user actually edits the reading. `line` is the lyric line the word sits in,
  /// pipe-encoded so a flashcard captured from this editor keeps its source line.
  func beginEditing(surface: String, reading: String, line: AnnotatedLine? = nil) {
    withAnimation(Motion.pop) {
      editingReading = ReadingEdit(
        surface: surface,
        reading: reading,
        rememberEverywhere: hasPersistedOverride(surface: surface),
        sourceLine: line.map { SourceLineCodec.encode($0.tokens) },
        sourceLineStartMs: line?.timeMs,
        sourceLineEndMs: line?.timeMs.flatMap(nextLineStart(after:))
      )
    }
  }

  /// The start time (ms) of the first synced line after `startMs` — the end of
  /// the line at `startMs` — so a captured flashcard can bound playback to just
  /// that line. Nil when it's the last timed line (or lyrics are unsynced).
  private func nextLineStart(after startMs: Int) -> Int? {
    lines.compactMap(\.timeMs).filter { $0 > startMs }.min()
  }

  /// Whether `surface` already has a personal override persisted for the signed-in
  /// user (a `.local` or `.synced` row — tombstoned `.pendingDelete` rows are
  /// excluded by `cache.overrides`). Drives the editor's pre-armed Remember toggle.
  private func hasPersistedOverride(surface: String) -> Bool {
    guard let userID = currentUserID else { return false }
    let key = surface.trimmingCharacters(in: .whitespacesAndNewlines)
    return cache.overrides(forUserID: userID)[key] != nil
  }

  /// Whether the word currently open in the editor is already in the flashcard
  /// deck, for the editor's save toggle.
  var isEditingWordSaved: Bool {
    editingReading.map { flashcards.isSaved($0.surface) } ?? false
  }

  /// Toggle the open word in the flashcard deck (save if absent, remove if
  /// present), carrying the editor's current reading draft and the captured song
  /// context. The editor stays open; the lyric surface's saved marker updates from
  /// `FlashcardsState`.
  func toggleSaveCurrentWord(reading: String) {
    // Flashcards are reserved for a permanent account; a guest gets the sign-in
    // prompt instead of a silent no-op.
    guard auth.requirePermanentAccount() else { return }
    guard let edit = editingReading else { return }
    let reading = reading.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !reading.isEmpty else { return }
    let track = music.currentTrack
    let input = SaveFlashcardInput(
      surface: edit.surface,
      reading: reading,
      sourceTitle: track?.title,
      sourceArtist: track?.artistDisplayName,
      sourceLine: edit.sourceLine,
      sourceLineStartMs: edit.sourceLineStartMs,
      sourceLineEndMs: edit.sourceLineEndMs,
      // Capture the playing track's provider + id so study can start this song
      // later (connecting if needed), the way Library replays a saved song.
      sourceProvider: track?.provider.rawValue,
      sourceTrackID: track?.providerTrackID
    )
    Task { await flashcards.toggleSave(input) }
  }

  /// Dismiss the editor without recording anything.
  func cancelEditing() {
    withAnimation(Motion.pop) { editingReading = nil }
  }

  /// Commit the open edit: route the card's draft through `recordOverride` (which
  /// handles the persist / session-only / sync / offline-queue branches), then
  /// close. The draft is passed in from the editor card rather than read back from
  /// `editingReading`, so the closing card never depends on this state.
  func commitEditing(reading: String, rememberEverywhere: Bool) {
    guard let surface = editingReading?.surface else { return }
    recordOverride(
      surface: surface,
      reading: reading,
      applyToAllSongs: rememberEverywhere
    )
    withAnimation(Motion.pop) { editingReading = nil }
  }

  /// Record a reading edit from the inline editor. When **Apply to all songs** is
  /// on, the `(surface, reading)` pair is persisted as a personal override
  /// (`OverrideEntity` `source = .local`, then uploaded) and reconciled across the
  /// open document; when off, it rewrites only the current rendering for the
  /// session.
  func recordOverride(surface: String, reading: String, applyToAllSongs: Bool) {
    let reading = reading.trimmingCharacters(in: .whitespacesAndNewlines)
    let surface = surface.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !reading.isEmpty, !surface.isEmpty else { return }

    if applyToAllSongs, let userID = currentUserID {
      // Optimistic local write first, so the re-render reflects the edit before
      // any network round-trip; the upload promotes the row to `synced` on success.
      cache.upsertOverride(userID: userID, surface: surface, reading: reading, source: .local)
      sessionOverrides[surface] = nil
      reannotate()
      Task { [weak self] in
        await self?.syncOverride(userID: userID, surface: surface, reading: reading)
      }
    } else {
      // Toggle off (or signed out): session-only, never persisted or uploaded.
      sessionOverrides[surface] = reading
      reannotate()
    }
  }

  /// The override map for the current annotation pass: persisted overrides for the
  /// signed-in user, with any session-only edits layered on top. Both take
  /// precedence over the bundled seed inside `CorrectionMap`.
  private func currentCorrectionMap() -> CorrectionMap {
    var overrides = currentUserID.map(cache.overrides(forUserID:)) ?? [:]
    for (surface, reading) in sessionOverrides {
      overrides[surface] = reading
    }
    return CorrectionMap.withSeed(userOverrides: overrides)
  }

  /// Re-run the annotator over the cached body with the latest override map, so an
  /// edit (or a freshly-synced override) takes effect within a render frame and
  /// with no `/api/lyrics` round-trip. The single annotation seam: the initial load
  /// and every override change share `reannotateTask`, so the newest pass always
  /// cancels and outlives any in-flight one.
  ///
  /// `showingLoadingIndicator` drives the "adding furigana" indicator — on for the
  /// cold initial load, off for the fast warm re-runs an edit triggers, so a small
  /// correction doesn't flash it. `reloadsTranslation` re-fetches the overlay after
  /// the load lands (cache-first; a reading edit leaves line text unchanged, so the
  /// edit path leaves it alone).
  private func reannotate(showingLoadingIndicator: Bool = false, reloadsTranslation: Bool = false) {
    guard let body = loadedBody else { return }
    let corrections = currentCorrectionMap()
    reannotateTask?.cancel()
    if showingLoadingIndicator { furiganaLoading = true }
    reannotateTask = Task { [weak self] in
      guard let self else { return }
      do {
        let annotated = try await annotator.annotate(lrcBody: body, corrections: corrections)
        guard !Task.isCancelled else { return }
        lines = annotated
        furiganaLoading = false
        if reloadsTranslation, showTranslation { loadTranslation() }
      } catch {
        // Tokenization failed — the plain lines are still on screen and readable,
        // so just drop the indicator rather than blanking the surface.
        if !Task.isCancelled { furiganaLoading = false }
      }
    }
  }

  /// Upload a single override; leaves the row `source = .local` (queued) on failure
  /// or while offline, for the next online tick to retry.
  private func syncOverride(userID: String, surface: String, reading: String) async {
    guard network.isOnline else { return }
    do {
      try await corrections.upsert(surface: surface, reading: reading)
      cache.markOverrideSynced(userID: userID, surface: surface)
    } catch {
      // Stay local; `observeReconnect` / a later edit will retry the flush.
    }
  }

  /// Flush queued override writes for the signed-in user, then pull the server's
  /// rows down. Order matters: uploads (`source = .local`, upsert) and deletions
  /// (`source = .pendingDelete`, DELETE) go up *first* so the server reflects this
  /// device's edits, then `reconcileOverrides` pulls — last-writer-wins by
  /// `updated_at` — so a tombstone still owed a `DELETE` isn't resurrected and a
  /// fresh local edit isn't clobbered. Runs on launch (when signed in) and on every
  /// reconnect. After the pull, re-annotate so a server override applies to the open
  /// song without a reload.
  func syncPendingOverrides() async {
    guard network.isOnline, let userID = currentUserID else { return }
    for pending in cache.pendingOverrides(forUserID: userID) {
      await syncOverride(userID: userID, surface: pending.surface, reading: pending.reading)
    }
    for surface in cache.pendingDeletes(forUserID: userID) {
      do {
        try await corrections.delete(surface: surface)
        cache.removeOverride(userID: userID, surface: surface)
      } catch {
        // Stay tombstoned; the next reconnect retries the DELETE.
      }
    }
    // The same seam drains the flashcard deck's queued writes/deletes and pulls
    // the server's rows, so a card saved or graded offline syncs on reconnect.
    await flashcards.flushPending()
    guard let serverRows = try? await corrections.fetchAll() else { return }
    cache.reconcileOverrides(userID: userID, serverRows: serverRows)
    reannotate()
  }

  /// Flush queued overrides whenever the device transitions back online. Re-arms
  /// after each change because `withObservationTracking` fires once per
  /// registration (mirrors `observeCurrentTrack`).
  private func observeReconnect() {
    withObservationTracking {
      _ = network.isOnline
    } onChange: {
      Task { @MainActor [weak self] in
        guard let self else { return }
        if network.isOnline { await syncPendingOverrides() }
        observeReconnect()
      }
    }
  }

  /// Re-translate the visible overlay when the user switches language in Settings.
  /// Without this the overlay keeps showing the previous target's cached result
  /// (e.g. ja) after picking 中文, since `loadTranslation` otherwise only runs on
  /// toggle or track change. Re-arms after each change because
  /// `withObservationTracking` fires once per registration (mirrors
  /// `observeCurrentTrack`).
  private func observeLanguage() {
    withObservationTracking {
      _ = preferences.language
    } onChange: {
      Task { @MainActor [weak self] in
        guard let self else { return }
        if showTranslation {
          // Drop the stale lines so the previous language's text doesn't linger
          // behind the loading state while the new target is fetched.
          translatedLines = []
          loadTranslation()
        }
        observeLanguage()
      }
    }
  }

  /// The current session user's id in the lowercased-UUID form used for
  /// `OverrideEntity` rows and the `reading_overrides.user_id` column; nil only
  /// while no session exists. Resolves for a guest *or* a permanent account — the
  /// reading editor and overrides are available to guests, scoped to the
  /// anonymous user id (which survives a later upgrade in place).
  private var currentUserID: String? {
    auth.sessionUserID?.uuidString.lowercased()
  }

  // MARK: Translation

  /// Toggle the whole-body translation overlay. Turning it on loads the
  /// translation (cache-first); turning it off clears it and cancels any in-flight
  /// request.
  func toggleTranslation() {
    showTranslation.toggle()
    if showTranslation {
      loadTranslation()
    } else {
      translationTask?.cancel()
      translatedLines = []
      translationStatus = .idle
    }
  }

  /// Load the current track's translation through the read-through cache: a cache
  /// hit renders with no network call, an online miss calls `/api/translate`, and
  /// an offline miss surfaces a transient notice and reverts the toggle.
  private func loadTranslation() {
    guard showTranslation, let track = music.currentTrack, !lines.isEmpty else { return }
    let sourceLines = lines
    let target = preferences.translationTarget
    let sourceText = sourceLines.map(\.text).joined(separator: "\n")

    translationTask?.cancel()
    translationStatus = .loading
    translationTask = Task { [weak self] in
      guard let self else { return }
      for await event in translation.load(
        songID: track.id,
        language: target,
        sourceText: sourceText
      ) {
        if Task.isCancelled { return }
        applyTranslation(event, sourceTexts: sourceLines.map(\.text))
      }
    }
  }

  private func applyTranslation(_ event: CacheLoad<TranslationPayload>, sourceTexts: [String]) {
    switch event {
    case let .value(payload):
      // Align by non-empty line order, not by raw index. The translate API
      // trims the lyrics (dropping leading/trailing blank lines and per-line
      // whitespace) before sending them to the model, so the response can
      // disagree with the source on blank-line count or position. Indexing by
      // raw position then shifts every translation down by one. Instead, hand
      // each non-empty source line the next non-empty translation line; blank
      // source lines carry no translation and never consume a slot.
      let translatedLineQueue = payload.bodyJson
        .components(separatedBy: "\n")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
      var nextTranslation = 0
      translatedLines = sourceTexts.map { text in
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              nextTranslation < translatedLineQueue.count
        else { return "" }
        defer { nextTranslation += 1 }
        return translatedLineQueue[nextTranslation]
      }
      translationStatus = .loaded
    case .unavailableOffline:
      revertTranslation(to: .unavailableOffline)
    case .notFound, .failed:
      revertTranslation(to: .unavailable)
    }
  }

  /// Surface a transient unavailable notice and flip the toggle back off, then
  /// clear the notice after a few seconds so it doesn't linger.
  private func revertTranslation(to status: TranslationStatus) {
    showTranslation = false
    translatedLines = []
    translationStatus = status
    noticeResetTask?.cancel()
    noticeResetTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(3))
      guard let self, !Task.isCancelled else { return }
      if translationStatus == status { translationStatus = .idle }
    }
  }
}
