import SwiftUI

/// Settings: appearance + language preferences, music-provider selection +
/// connect / disconnect, and sign out. The provider picker switches the active
/// provider (tearing the previous one down); connect /
/// disconnect then act on whichever provider is selected.
/// Forms stay on the system opaque material per the chrome-vs-content split.
struct SettingsView: View {
  @Environment(AuthService.self) private var auth
  @Environment(MusicState.self) private var music
  @Environment(PreferencesState.self) private var preferences

  @State private var isConnecting = false
  @State private var connectError: String?

  var body: some View {
    @Bindable var preferences = preferences
    return NavigationStack {
      Form {
        Section("Appearance") {
          Picker("Theme", selection: $preferences.theme) {
            ForEach(ThemePreference.allCases) { theme in
              Text(theme.label).tag(theme)
            }
          }
          Picker("Language", selection: $preferences.language) {
            ForEach(LanguagePreference.allCases) { language in
              Text(language.label).tag(language)
            }
          }
        }

        Section("Music") {
          Picker("Provider", selection: providerSelection) {
            ForEach(music.availableProviders) { provider in
              Text(provider.displayName).tag(MusicProvider?.some(provider))
            }
          }

          if let provider = music.activeProvider {
            if music.isConnected {
              Label("\(provider.displayName) connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
              Button("Disconnect \(provider.displayName)", role: .destructive) {
                Task { await music.disconnect() }
              }
            } else {
              Button(action: connect) {
                Label("Connect \(provider.displayName)", systemImage: "link")
              }
              .disabled(isConnecting)
              if let connectError {
                Text(connectError)
                  .font(Typography.metadata)
                  .foregroundStyle(.secondary)
              }
            }
          } else {
            Text("Choose a provider to connect.")
              .font(Typography.metadata)
              .foregroundStyle(.secondary)
          }
        }

        Section("Customization") {
          NavigationLink {
            ReadingOverridesView()
          } label: {
            Label("Reading Overrides", systemImage: "character.book.closed")
          }
        }

        Section {
          Button("Sign Out", role: .destructive) {
            Task { await auth.signOut() }
          }
        }
      }
      .navigationTitle("Settings")
    }
  }

  /// Drives the provider picker. Selecting a provider switches `MusicState` to it,
  /// which tears the previous adapter down exactly once before activating the new
  /// one. The new provider starts disconnected — the Connect row below
  /// the picker takes it from there.
  private var providerSelection: Binding<MusicProvider?> {
    Binding(
      get: { music.activeProvider },
      set: { provider in
        guard let provider else { return }
        connectError = nil
        Task {
          await music.select(provider)
          // Apple Music's adapter only starts observing player state once
          // connected (`MusicKitAdapter.startObserving`), so an unconnected
          // session leaves the play/pause button and lyrics highlight stuck
          // after the first pause — the audio pauses but no update is emitted.
          // Its connect is just a non-disruptive system authorization prompt
          // (no app switch like Spotify), so connect it eagerly on selection
          // to bring observation live before the user plays. Spotify stays
          // manual — its connect bounces out to the Spotify app.
          if provider == .appleMusic {
            await connectActiveProvider()
          }
        }
      }
    )
  }

  private func connect() {
    Task { await connectActiveProvider() }
  }

  private func connectActiveProvider() async {
    isConnecting = true
    connectError = nil
    let result = await music.connect()
    isConnecting = false
    if case let .failure(error) = result {
      // `notInstalled` → "Spotify isn't installed."; silent reasons
      // (userCancelled / cancelled) leave the row untouched.
      connectError = error.userMessage
    }
  }
}
