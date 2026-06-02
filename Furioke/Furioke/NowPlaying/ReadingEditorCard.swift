import SwiftUI

/// The focus-overlay reading editor: a glass card that floats over the dimmed
/// lyric column when the reader long-presses a word. It echoes the targeted
/// surface and, for a kanji word, offers a legible field to correct its reading;
/// Save reports the draft back via `onSave`, which the surface routes through
/// `recordOverride`.
///
/// The editable draft lives in this view's own `@State` (seeded once from the
/// initial values) rather than a binding into the surface's optional edit state.
/// That keeps the card self-contained while it animates out: once the edit is
/// cleared, the closing card reads only its own state, never a now-nil optional.
///
/// Chrome-vs-content split: the card *frame* is glass
/// — it floats over a refractable backdrop, the lyric wash — while the editable
/// field sits on an opaque `Surface` inset so the kana stays crisp.
struct ReadingEditorCard: View {
  let surface: String
  /// Whether the word's reading can be corrected (it contains kanji). When false
  /// the card shows no reading field, Remember toggle, or Save — only the surface.
  let correctable: Bool
  /// Whether to show the **Remember this reading** toggle. The playback overlay
  /// shows it (persist-everywhere vs. session-only); the overrides manager hides
  /// it — there the override is already persisted, so "remember" is meaningless and
  /// the edit always saves with `rememberEverywhere == true`.
  let showsRememberToggle: Bool
  /// Whether to show the **Save to flashcards** toggle — the lyric-surface capture
  /// affordance. The playback overlay shows it for a kanji word; the overrides
  /// manager hides it.
  let showsSaveToFlashcards: Bool
  let onCancel: () -> Void
  let onSave: (_ reading: String, _ rememberEverywhere: Bool) -> Void
  /// Toggle the word in the deck, carrying the current reading draft so a saved
  /// card uses the corrected reading. Called as the toggle flips.
  let onToggleSave: (_ reading: String) -> Void

  @State private var reading: String
  @State private var rememberEverywhere: Bool
  @State private var saved: Bool
  @FocusState private var fieldFocused: Bool

  /// The reading as it stood when the card opened (trimmed), so we can tell a real
  /// correction from an untouched Save and auto-arm the Remember toggle only when
  /// the user actually changes the reading.
  private let originalReading: String

  /// Whether the word already had a persisted override when the card opened. It
  /// keeps the **Remember this reading** toggle shown and checked for an
  /// already-overridden word even before the reading is touched, and is the floor
  /// the auto-arm never drops below (reverting to the override value stays armed).
  private let initiallyRemembered: Bool

  init(
    surface: String,
    correctable: Bool = true,
    initialReading: String,
    initialRemember: Bool,
    showsRememberToggle: Bool = true,
    showsSaveToFlashcards: Bool = false,
    initialSaved: Bool = false,
    onCancel: @escaping () -> Void,
    onSave: @escaping (String, Bool) -> Void,
    onToggleSave: @escaping (String) -> Void = { _ in }
  ) {
    self.surface = surface
    self.correctable = correctable
    self.showsRememberToggle = showsRememberToggle
    self.showsSaveToFlashcards = showsSaveToFlashcards
    self.onCancel = onCancel
    self.onSave = onSave
    self.onToggleSave = onToggleSave
    _reading = State(initialValue: initialReading)
    _rememberEverywhere = State(initialValue: initialRemember)
    _saved = State(initialValue: initialSaved)
    originalReading = initialReading.trimmingCharacters(in: .whitespacesAndNewlines)
    initiallyRemembered = initialRemember
  }

  /// Whether the draft is worth a Remember toggle: either the word already carries
  /// a persisted override, or the reading has been edited away from what the card
  /// opened with. The toggle is hidden until this is true, so an untouched word
  /// shows nothing to remember (mirroring the auto-arm condition).
  private var hasChange: Bool {
    initiallyRemembered || trimmedReading != originalReading
  }

  private var trimmedReading: String {
    reading.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Mirrors the spec's "Empty reading cannot be confirmed" — Save is disabled
  /// until the field holds a non-blank reading.
  private var canSave: Bool {
    !trimmedReading.isEmpty
  }

  var body: some View {
    GlassChrome(role: Materials.chromeGlass) {
      VStack(alignment: .leading, spacing: Spacing.l) {
        editorRow
        if correctable, showsRememberToggle, hasChange {
          rememberToggle
        }
        if correctable, showsSaveToFlashcards {
          saveToggle
        }
        buttons
      }
      .padding(Spacing.l)
    }
    .frame(maxWidth: 360)
    .onAppear { if correctable { fieldFocused = true } }
    .onChange(of: reading) { _, newValue in
      // Remember tracks edited-state: a real correction persists everywhere, an
      // untouched (or reverted-to-original) reading stays session-only. Driven off
      // every change so reverting to the original auto-disarms it too — but an
      // already-overridden word stays armed (`initiallyRemembered`), since its
      // displayed reading *is* the override.
      rememberEverywhere = initiallyRemembered
        || newValue.trimmingCharacters(in: .whitespacesAndNewlines) != originalReading
    }
  }

  /// The targeted word and — for a kanji word — its editable reading on one line:
  /// the surface echoes what's being acted on, the field carries the reading fix.
  /// A kana word shows just the surface (nothing to correct).
  private var editorRow: some View {
    HStack(spacing: Spacing.m) {
      Text(surface)
        .font(Typography.lyricActive)
      if correctable {
        field
      }
    }
  }

  /// The opaque field inset — readability of the kana beats continuity with the
  /// glass frame.
  private var field: some View {
    Surface(material: Materials.contentSurface, cornerRadius: Radii.md) {
      HStack(spacing: Spacing.s) {
        TextField("Reading", text: $reading)
          .font(.system(.title3, design: .rounded))
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .focused($fieldFocused)
          .submitLabel(.done)
          .onSubmit { if canSave { onSave(trimmedReading, rememberEverywhere) } }
        if !reading.isEmpty {
          Button {
            reading = ""
          } label: {
            Image(systemName: "xmark.circle.fill")
              .foregroundStyle(.tertiary)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Clear reading")
        }
      }
      .padding(.horizontal, Spacing.m)
      .padding(.vertical, Spacing.s)
    }
    .frame(maxWidth: .infinity)
  }

  /// A glass pill that toggles whether the correction is remembered everywhere.
  /// It lights up when on — the same lit-glass idiom the NowPlaying display
  /// controls use — instead of a system switch.
  private var rememberToggle: some View {
    Button {
      rememberEverywhere.toggle()
    } label: {
      HStack(spacing: Spacing.s) {
        Image(systemName: rememberEverywhere ? "checkmark.circle.fill" : "circle")
        Text("Remember this reading")
          .font(Typography.metadata)
      }
      .foregroundStyle(rememberEverywhere ? .primary : .secondary)
      .padding(.horizontal, Spacing.m)
      .padding(.vertical, Spacing.s)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .background(
      Capsule().fill(Color.primary.opacity(rememberEverywhere ? 0 : 0.06))
    )
    .glassEffect(Materials.controlTier.glass(active: rememberEverywhere), in: Capsule())
    .accessibilityLabel("Remember this reading")
    .accessibilityValue(rememberEverywhere ? "On" : "Off")
    .accessibilityAddTraits(.isButton)
  }

  /// A glass pill that saves the word to the flashcard deck (or removes it),
  /// lit when the word is in the deck — the same lit-glass idiom as the Remember
  /// toggle. Carries the current reading draft so a saved card uses the correction.
  private var saveToggle: some View {
    Button {
      saved.toggle()
      onToggleSave(trimmedReading)
    } label: {
      HStack(spacing: Spacing.s) {
        Image(systemName: saved ? "checkmark.circle.fill" : "circle")
        Text("Save to flashcards")
          .font(Typography.metadata)
      }
      .foregroundStyle(saved ? .primary : .secondary)
      .padding(.horizontal, Spacing.m)
      .padding(.vertical, Spacing.s)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .background(
      Capsule().fill(Color.primary.opacity(saved ? 0 : 0.06))
    )
    .glassEffect(Materials.controlTier.glass(active: saved), in: Capsule())
    .disabled(!canSave)
    .opacity(canSave ? 1 : 0.5)
    .accessibilityLabel("Save to flashcards")
    .accessibilityValue(saved ? "Saved" : "Not saved")
    .accessibilityAddTraits(.isButton)
  }

  private var buttons: some View {
    HStack {
      // A non-correctable card has no reading to commit, so its single dismiss
      // button reads "Done" rather than "Cancel".
      Button(correctable ? "Cancel" : "Done", role: .cancel, action: onCancel)
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
      if correctable {
        Spacer()
        Button {
          onSave(trimmedReading, rememberEverywhere)
        } label: {
          Text("Save")
            .font(Typography.metadata.weight(.semibold))
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.s)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(Materials.controlTier.glass(active: canSave), in: Capsule())
        .opacity(canSave ? 1 : 0.5)
        .disabled(!canSave)
      }
    }
    .font(Typography.metadata)
  }
}
