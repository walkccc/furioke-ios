import SwiftUI

/// The shared music-provider picker: a row of equal-width selectable columns,
/// each showing a provider's brand icon and display name. A column is
/// highlighted only while that provider is the currently-connected one; tapping
/// a column selects that provider and immediately connects it (a no-op when it
/// is already the connected provider). While a connect is in flight the tapped
/// column shows a progress indicator, and a non-silent connect failure surfaces
/// the error's `userMessage` below the grid.
///
/// Connect is best-effort and never blocks the caller — the Settings tab and the
/// onboarding setup step render the same control, and onboarding stays
/// advanceable regardless of the connect result (including when Spotify bounces
/// out to its app for authorization).
struct ProviderSelector: View {
  @Environment(MusicState.self) private var music

  @State private var isConnecting = false
  @State private var connectError: String?

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.m) {
      grid
      // The only thing that ever appears below the grid is a connect-failure note.
      if let connectError {
        Text(LocalizedStringKey(connectError))
          .font(Typography.metadata)
          .foregroundStyle(.secondary)
      }
    }
  }

  /// Three provider columns: each shows the provider's brand icon + name. A
  /// column is highlighted only while that provider is the connected one — when
  /// nothing is connected, nothing is highlighted. Tapping a column selects that
  /// provider and connects it.
  private var grid: some View {
    HStack(spacing: Spacing.s) {
      ForEach(music.availableProviders) { provider in
        let isConnectedProvider = music.activeProvider == provider && music.isConnected
        let isConnectingProvider = isConnecting && music.activeProvider == provider && !music
          .isConnected
        ProviderOptionCard(
          label: provider.displayName,
          iconAsset: providerIcon(provider),
          isSelected: isConnectedProvider,
          isConnecting: isConnectingProvider,
          action: { selectProvider(provider) }
        )
      }
    }
  }

  private func providerIcon(_ provider: MusicProvider) -> String {
    switch provider {
    case .spotify: "SpotifyIcon"
    case .appleMusic: "AppleMusicIcon"
    case .youtube: "YoutubeMusicIcon"
    }
  }

  /// Tapping a provider switches `MusicState` to it (tearing the previous adapter
  /// down exactly once) and immediately connects it — there is no separate
  /// connect step. `select` is a no-op when the provider is already active, so a
  /// tap on a selected-but-disconnected provider just retries the connect.
  /// Connecting is also what brings player-state observation live, so
  /// auto-connecting on tap is what keeps the transport and lyrics highlight
  /// responsive; Spotify's connect bounces out to the Spotify app for
  /// authorization. The flow never blocks on the result.
  private func selectProvider(_ provider: MusicProvider) {
    // Already the connected provider — nothing to do.
    if music.activeProvider == provider, music.isConnected { return }
    connectError = nil
    Task {
      await music.select(provider)
      isConnecting = true
      let result = await music.connect()
      isConnecting = false
      if case let .failure(error) = result {
        // `notInstalled` → "Spotify isn't installed."; silent reasons
        // (userCancelled / cancelled) leave the row untouched.
        connectError = error.userMessage
      }
    }
  }
}

/// One provider column: a brand icon over a label. The connected provider is
/// highlighted with an accent fill + ring (no checkmark, kept minimal); while
/// connecting, the icon dims under a progress spinner. Shared by Settings and
/// onboarding so both render an identical control.
struct ProviderOptionCard: View {
  let label: String
  let iconAsset: String
  let isSelected: Bool
  let isConnecting: Bool
  let action: () -> Void

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Radii.md, style: .continuous)
    Button(action: action) {
      VStack(spacing: Spacing.xs) {
        Image(iconAsset)
          .renderingMode(.original)
          .resizable()
          .scaledToFit()
          .frame(height: 30)
          .opacity(isConnecting ? 0.35 : 1)
          .overlay {
            if isConnecting {
              ProgressView()
            }
          }
        // Provider brand names aren't catalog keys, so they fall through verbatim.
        Text(label)
          .font(Typography.metadata)
          .lineLimit(1)
          .minimumScaleFactor(0.75)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, Spacing.m)
      .foregroundStyle(isSelected ? Color.accentColor : .primary)
      .background(
        // Unselected cells stay barely-there so a transparent pane (and the
        // backdrop behind it) reads through them; the selected cell fills with
        // accent so the choice still pops against the glass.
        shape.fill(isSelected ? Color.accentColor.opacity(0.18) : Color(.quaternarySystemFill))
      )
      .overlay(
        shape.strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
      )
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    .accessibilityLabel(Text(label))
  }
}
