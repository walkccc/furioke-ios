import SwiftUI

/// Review-and-cleanup surface for the signed-in user's reading overrides, pushed
/// from Settings. Lists each `kanji → reading` the user has corrected during
/// playback with a sync badge; supports search, swipe-to-delete, and tap-to-edit
/// (reusing `ReadingEditorCard`). Only the user's own overrides appear — the
/// bundled `seed.json` corrections are part of the annotator baseline and never
/// surface here. Edits and deletes re-annotate lyrics on the next song load, not
/// live.
struct ReadingOverridesView: View {
  @Environment(ReadingOverridesState.self) private var state

  /// The override currently open in the reading editor overlay, or nil when closed.
  @State private var editing: ReadingOverride?

  var body: some View {
    content
      .navigationTitle("Reading Overrides")
      .navigationBarTitleDisplayMode(.inline)
      .onAppear { state.reload() }
      .task { await state.sync() }
      .overlay { editorOverlay }
  }

  @ViewBuilder
  private var content: some View {
    if !state.isSignedIn {
      EmptyState(
        systemImage: "person.crop.circle.badge.questionmark",
        title: "Sign In Required",
        message: "Overrides are saved per account. Sign in to review and manage your reading corrections."
      )
    } else if state.rows.isEmpty {
      EmptyState(
        systemImage: "character.book.closed",
        title: "No Overrides Yet",
        message: "Long-press a word in Now Playing to correct its reading. Your corrections appear here."
      )
    } else {
      overridesList
    }
  }

  private var overridesList: some View {
    List {
      ForEach(state.rows) { override in
        Button {
          withAnimation(Motion.pop) { editing = override }
        } label: {
          row(override)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
          Button(role: .destructive) {
            Task { await state.delete(override) }
          } label: {
            Label("Delete", systemImage: "trash")
          }
        }
      }
    }
  }

  /// One override row: the corrected reading over its surface, plus a sync badge.
  private func row(_ override: ReadingOverride) -> some View {
    HStack(spacing: Spacing.m) {
      VStack(alignment: .leading, spacing: Spacing.xs) {
        Text(override.surface)
          .font(Typography.lyricRest)
        Text(override.reading)
          .font(Typography.metadata)
          .foregroundStyle(.secondary)
      }
      Spacer()
      syncBadge(isPending: override.isPendingSync)
    }
    .contentShape(Rectangle())
  }

  /// "Synced" vs "Pending" — pending means the row is a local edit not yet uploaded
  /// (offline or awaiting the next sync). `.pendingDelete` rows never reach the list.
  private func syncBadge(isPending: Bool) -> some View {
    Label(
      isPending ? "Pending" : "Synced",
      systemImage: isPending ? "arrow.triangle.2.circlepath" : "checkmark.icloud"
    )
    .labelStyle(.titleAndIcon)
    .font(Typography.metadata)
    .foregroundStyle(isPending ? .orange : .secondary)
  }

  /// The dimming scrim + reading editor, shown while an edit is open. Mirrors the
  /// playback overlay in `AppShell`, minus the "remember" toggle — the override is
  /// already persisted, so editing it simply overwrites the reading.
  @ViewBuilder
  private var editorOverlay: some View {
    if let override = editing {
      ZStack(alignment: .bottom) {
        DimScrim { withAnimation(Motion.pop) { editing = nil } }
        ReadingEditorCard(
          surface: override.surface,
          initialReading: override.reading,
          initialRemember: true,
          showsRememberToggle: false,
          onCancel: { withAnimation(Motion.pop) { editing = nil } },
          onSave: { reading, _ in
            Task { await state.updateReading(surface: override.surface, reading: reading) }
            withAnimation(Motion.pop) { editing = nil }
          }
        )
        .padding(.horizontal, Spacing.l)
        .padding(.bottom, Spacing.l)
        .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
  }
}
