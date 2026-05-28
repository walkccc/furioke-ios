import SwiftUI

/// The focus-overlay reading editor: a glass card that floats over the dimmed
/// lyric column when the reader long-presses a kanji word. It echoes the targeted
/// surface and offers a legible field to correct its reading; Save reports the
/// draft back via `onSave`, which the surface routes through `recordOverride`.
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
  /// Whether to show the **Remember this reading** toggle. The playback overlay
  /// shows it (persist-everywhere vs. session-only); the overrides manager hides
  /// it — there the override is already persisted, so "remember" is meaningless and
  /// the edit always saves with `rememberEverywhere == true`.
  let showsRememberToggle: Bool
  let onCancel: () -> Void
  let onSave: (_ reading: String, _ rememberEverywhere: Bool) -> Void

  @State private var reading: String
  @State private var rememberEverywhere: Bool
  @FocusState private var fieldFocused: Bool

  init(
    surface: String,
    initialReading: String,
    initialRemember: Bool,
    showsRememberToggle: Bool = true,
    onCancel: @escaping () -> Void,
    onSave: @escaping (String, Bool) -> Void
  ) {
    self.surface = surface
    self.showsRememberToggle = showsRememberToggle
    self.onCancel = onCancel
    self.onSave = onSave
    _reading = State(initialValue: initialReading)
    _rememberEverywhere = State(initialValue: initialRemember)
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
        if showsRememberToggle {
          rememberToggle
        }
        buttons
      }
      .padding(Spacing.l)
    }
    .frame(maxWidth: 360)
    .onAppear { fieldFocused = true }
  }

  /// The targeted kanji and its editable reading on one line — the surface echoes
  /// what's being corrected, the field carries the fix.
  private var editorRow: some View {
    HStack(spacing: Spacing.m) {
      Text(surface)
        .font(Typography.lyricActive)
      field
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
    .glassEffect(litGlass(isOn: rememberEverywhere), in: Capsule())
    .accessibilityLabel("Remember this reading")
    .accessibilityValue(rememberEverywhere ? "On" : "Off")
    .accessibilityAddTraits(.isButton)
  }

  private var buttons: some View {
    HStack {
      Button("Cancel", role: .cancel, action: onCancel)
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
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
      .glassEffect(litGlass(isOn: canSave), in: Capsule())
      .opacity(canSave ? 1 : 0.5)
      .disabled(!canSave)
    }
    .font(Typography.metadata)
  }

  /// Interactive control-tier glass, brightened with a white tint when "on" so the
  /// active state reads as a lit pill (mirrors `NowPlayingContent`'s display discs).
  private func litGlass(isOn: Bool) -> Glass {
    isOn
      ? Materials.controlTier.glass.tint(.white.opacity(0.4))
      : Materials.controlTier.glass
  }
}
