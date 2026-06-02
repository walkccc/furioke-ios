import SwiftUI

/// The root of the 単語 (Tango) tab: a Quizlet-style swipe deck of due cards over
/// the artwork backdrop. Tap the top card to flip it (front ↔ back); swipe left to
/// forget (`.again`, re-queued) or right to remember (`.gotIt`, advances the
/// schedule). The deck browse list is a "browse" destination reached from the
/// toolbar; the recognition mode is chosen from the display-mode menu.
struct TangoView: View {
  @Environment(FlashcardsState.self) private var flashcards
  @Environment(MusicState.self) private var music
  @Environment(AuthService.self) private var auth

  @AppStorage("furioke.study.mode") private var modeRaw = StudyMode.glance.rawValue

  /// The remaining due cards this session; index 0 is the top card. Re-queued
  /// `.again` cards go to the back.
  @State private var queue: [Flashcard] = []
  /// Cards in the queue when the session was seeded, for the progress indicator.
  @State private var initialCount = 0
  /// True once the learner has graded a card, so a background sync doesn't reseed
  /// mid-session.
  @State private var started = false
  @State private var isFlipped = false
  @State private var drag: CGSize = .zero

  /// Consecutive "Got it" grades this session; reset by an "Again". Surfaced as a
  /// combo badge once it's worth celebrating. Session-local, never persisted.
  @State private var combo = 0
  /// Bumped on every committed grade to drive the grade-commit haptic.
  @State private var gradeTick = 0
  /// Bumped when a "Got it" promotes a card to a higher Leitner box, to drive the
  /// level-up haptic; `showLevelUp` shows the matching transient cue.
  @State private var levelUpTick = 0
  @State private var showLevelUp = false

  /// How far the top card must be dragged to commit a grade.
  private let threshold: CGFloat = 110

  private var mode: StudyMode {
    StudyMode(rawValue: modeRaw) ?? .glance
  }

  private var modeSelection: Binding<StudyMode> {
    Binding(get: { mode }, set: { modeRaw = $0.rawValue })
  }

  var body: some View {
    content
      .background(ArtworkBackdrop(url: music.currentTrack?.artworkURL))
      // The title + deck controls only make sense for a signed-in learner; when
      // signed out the nav bar is hidden entirely so the sign-in prompt centers in
      // the full screen, matching the Library tab's signed-out layout exactly.
      .toolbar(flashcards.isSignedIn ? .visible : .hidden, for: .navigationBar)
      .toolbar { tangoToolbar }
      .onAppear {
        flashcards.reload()
        if !started { seed() }
      }
      .task {
        await flashcards.sync()
        if !started { seed() }
      }
      // A light tap when the card is flipped to its back (not on the programmatic
      // reset to front), a firmer tap when a grade commits, and a success cue when
      // a card levels up — matching the lyric editor's `.sensoryFeedback` pattern.
      .sensoryFeedback(trigger: isFlipped) { _, flipped in flipped ? .impact(weight: .light) : nil }
      .sensoryFeedback(.impact(weight: .medium), trigger: gradeTick)
      .sensoryFeedback(.success, trigger: levelUpTick)
  }

  @ViewBuilder
  private var content: some View {
    if !flashcards.isSignedIn {
      prompt(
        systemImage: "person.crop.circle.badge.questionmark",
        title: "Sign In Required",
        message: "Flashcards are saved per account. Sign in to study the words you've saved from lyrics.",
        showsSignIn: true
      )
    } else if queue.isEmpty {
      // A drained session (we seeded cards and worked through them all) earns a
      // celebration; entering with nothing due shows the plain caught-up prompt.
      if initialCount > 0 {
        prompt(
          systemImage: "sparkles",
          title: "Session Complete",
          message: "You reviewed every card that was due. Come back when more are ready.",
          showsSignIn: false
        )
      } else {
        prompt(
          systemImage: "checkmark.circle",
          title: "All Caught Up",
          message: "No cards are due right now. Save words from song lyrics, or browse your deck.",
          showsSignIn: false
        )
      }
    } else {
      // Size the card from the available space so every card is identical and the
      // deck doesn't resize between cards (an aspect-fit over greedy content gave
      // a content-dependent size).
      GeometryReader { geo in
        let cardWidth = min(geo.size.width - Spacing.l * 2, 360)
        let cardHeight = min(cardWidth / 0.7, max(geo.size.height - 110, 240))
        VStack(spacing: Spacing.l) {
          progress
          cardStack(width: cardWidth, height: cardHeight)
            .overlay {
              if showLevelUp {
                levelUpCue.transition(.scale.combined(with: .opacity))
              }
            }
          Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, Spacing.l)
        .padding(.top, Spacing.m)
      }
    }
  }

  /// The centered sign-in / caught-up prompt, shared by the signed-out and the
  /// signed-in-but-no-due-cards states. Built on the shared `SignInPrompt` so it
  /// matches the Library tab exactly.
  private func prompt(
    systemImage: String,
    title: LocalizedStringKey,
    message: LocalizedStringKey,
    showsSignIn: Bool
  ) -> some View {
    SignInPrompt(
      systemImage: systemImage,
      title: title,
      message: message,
      showsSignIn: showsSignIn,
      onSignIn: { auth.presentSignInPrompt() }
    )
  }

  // MARK: Stack

  /// The deck, pinned to one explicit `width × height` so it never resizes between
  /// cards. Behind the top card sit blank, content-free surfaces for the stacked
  /// look. The *real* next card is rendered only while the top is sliding away (a
  /// drag or the commit fling): it sits at the top card's own size and position so
  /// it's revealed seamlessly as the top leaves, then lands without a pop when it
  /// becomes the next top. (The card surface itself is opaque, so a flip never
  /// shows the card behind it.)
  private func cardStack(width: CGFloat, height: CGFloat) -> some View {
    ZStack {
      ForEach(0 ..< behindCount, id: \.self) { index in
        let depth = behindCount - index
        EmptyFlashcardView()
          .scaleEffect(1 - CGFloat(depth) * 0.04)
          .offset(y: CGFloat(depth) * 12)
      }
      if isSwiping, queue.count > 1 {
        FlashcardView(card: queue[1], mode: mode, isFlipped: false)
      }
      if let top = queue.first {
        topCard(top)
      }
    }
    .frame(width: width, height: height)
    .frame(maxWidth: .infinity)
  }

  /// How many blank depth cards to stack behind the top (0–2).
  private var behindCount: Int {
    min(2, max(0, queue.count - 1))
  }

  /// True while the top card is being dragged or flung off — the only time the real
  /// next card is shown, so it never ghosts through the top card during a flip.
  private var isSwiping: Bool {
    drag != .zero
  }

  private func topCard(_ card: Flashcard) -> some View {
    FlashcardView(card: card, mode: mode, isFlipped: isFlipped)
      .offset(drag)
      .rotationEffect(.degrees(Double(drag.width / 18)))
      .overlay { gradeStamps }
      .gesture(
        DragGesture()
          .onChanged { drag = $0.translation }
          .onEnded { onDragEnded($0) }
      )
      // A drag past the touch slop cancels this tap, so a flip never fires
      // mid-drag; a clean tap flips the card.
      .onTapGesture {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { isFlipped.toggle() }
      }
  }

  /// The tinted directional affordances: FORGET to the left, REMEMBER to the
  /// right, each intensifying with the drag distance toward it.
  private var gradeStamps: some View {
    ZStack {
      stamp(text: "Forget", tint: .red, alignment: .topLeading)
        .opacity(stampOpacity(forLeft: true))
      stamp(text: "Remember", tint: .green, alignment: .topTrailing)
        .opacity(stampOpacity(forLeft: false))
    }
    .padding(Spacing.l)
  }

  private func stamp(text: LocalizedStringKey, tint: Color, alignment: Alignment) -> some View {
    Text(text)
      .font(.system(.headline, design: .rounded, weight: .heavy))
      .foregroundStyle(tint)
      .textCase(.uppercase)
      .padding(.horizontal, Spacing.m)
      .padding(.vertical, Spacing.s)
      .glassEffect(Materials.capsuleTier.glass.tint(tint.opacity(0.18)), in: Capsule())
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
  }

  private func stampOpacity(forLeft: Bool) -> Double {
    let directional = forLeft ? -drag.width : drag.width
    guard directional > 0 else { return 0 }
    return Double(min(directional / threshold, 1))
  }

  // MARK: Progress

  private var progress: some View {
    let done = max(0, initialCount - queue.count)
    return VStack(spacing: Spacing.xs) {
      ProgressView(value: Double(done), total: Double(max(initialCount, 1)))
        .tint(Color.accentColor)
      HStack(spacing: Spacing.s) {
        Text(verbatim: "\(done) / \(initialCount)")
        // A streak of correct grades is worth celebrating once it's going.
        if combo >= 2 {
          Label("\(combo)", systemImage: "flame.fill")
            .foregroundStyle(.orange)
            .transition(.scale.combined(with: .opacity))
        }
      }
      .font(Typography.metadata)
      .foregroundStyle(.secondary)
      .animation(Motion.pop, value: combo)
    }
  }

  /// The transient "Level up" cue shown briefly when a grade promotes a card.
  private var levelUpCue: some View {
    Label("Level up!", systemImage: "arrow.up.circle.fill")
      .font(.system(.headline, design: .rounded, weight: .heavy))
      .foregroundStyle(.white)
      .padding(.horizontal, Spacing.l)
      .padding(.vertical, Spacing.m)
      .glassEffect(Materials.capsuleTier.glass.tint(.green.opacity(0.55)), in: Capsule())
      .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
  }

  // MARK: Toolbar

  /// The title + deck controls, shown only for a signed-in learner — the signed-out
  /// state hides the nav bar (see `body`), so emitting no items keeps it bare.
  @ToolbarContentBuilder
  private var tangoToolbar: some ToolbarContent {
    if flashcards.isSignedIn {
      ToolbarItem(placement: .principal) { Text("Flashcards") }
      ToolbarItem(placement: .topBarLeading) { modeMenu }
      ToolbarItem(placement: .topBarTrailing) {
        NavigationLink { TangoListView() } label: {
          Label("Browse", systemImage: "list.bullet")
        }
      }
    }
  }

  // MARK: Display-mode menu

  private var modeMenu: some View {
    Menu {
      Picker(selection: modeSelection) {
        ForEach(StudyMode.allCases) { studyMode in
          Text(studyMode.label).tag(studyMode)
        }
      } label: {
        Text("Display mode")
      }
      .pickerStyle(.inline)
    } label: {
      Label("Display mode", systemImage: "textformat.alt")
    }
  }

  // MARK: Session

  private func seed() {
    queue = flashcards.dueCards
    initialCount = queue.count
    isFlipped = false
    drag = .zero
    combo = 0
    prefetchTop()
  }

  private func onDragEnded(_ value: DragGesture.Value) {
    let width = value.translation.width
    guard abs(width) > threshold, let card = queue.first else {
      withAnimation(Motion.pop) { drag = .zero }
      return
    }
    let grade: FlashcardGrade = width > 0 ? .gotIt : .again
    // Fling the card off-screen in the drag direction, then commit once it's gone.
    withAnimation(.easeIn(duration: 0.25)) {
      drag = CGSize(width: width > 0 ? 1_200 : -1_200, height: value.translation.height)
    }
    Task {
      try? await Task.sleep(for: .milliseconds(220))
      await commit(card, grade: grade)
    }
  }

  /// Persist the grade and advance the queue: `.gotIt` drops the card, `.again`
  /// re-queues it at the back of the session. Resets the top-card state for the
  /// next card.
  @MainActor
  private func commit(_ card: Flashcard, grade: FlashcardGrade) async {
    started = true
    // Feedback: build/break the combo, fire the grade haptic, and flag a level-up
    // when a "Got it" promotes the card to a higher Leitner box. Session-local only.
    let promoted = grade == .gotIt && card.level < FlashcardSchedule.maxLevel
    combo = grade == .gotIt ? combo + 1 : 0
    gradeTick += 1
    if promoted { flashLevelUp() }
    var rest = Array(queue.dropFirst())
    if grade == .again { rest.append(card) }
    // Reset flip/drag and advance the queue in one synchronous update (no animation,
    // so the new top mounts instantly): the revealed next card and the new top are
    // the same card at the same place, so it lands without a pop or fade.
    isFlipped = false
    drag = .zero
    queue = rest
    await flashcards.grade(card, grade)
    prefetchTop()
  }

  /// Trigger the level-up haptic and show the transient cue, auto-hiding it.
  private func flashLevelUp() {
    levelUpTick += 1
    withAnimation(Motion.pop) { showLevelUp = true }
    Task {
      try? await Task.sleep(for: .seconds(1.1))
      withAnimation(Motion.ease) { showLevelUp = false }
    }
  }

  /// Warm the top card's glosses so its back face isn't blank on first flip;
  /// failures degrade to word + reading + lyric.
  private func prefetchTop() {
    guard let top = queue.first else { return }
    Task {
      // `glossed` no-ops (no network) when the active language's gloss is already
      // present, so calling it for every new top is cheap. This is a silent warm-up,
      // not an explicit tap, so it never raises the out-of-quota toast — only the
      // back face's tap-to-translate does.
      let updated = await flashcards.glossed(top, raisesQuotaNotice: false)
      if queue.first?.id == updated.id { queue[0] = updated }
    }
  }
}
