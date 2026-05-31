import SwiftUI

enum AppTab: Hashable {
  case library
  case search
  case study
  case settings
}

// Four-tab native iOS 26 TabView. The Liquid Glass treatment of the bar
// itself is provided by the system; this view is just the typed composition
// root that names the destinations and hosts the persistent mini-player
// above the bar via `tabViewBottomAccessory`.

struct LiquidGlassTabBar<
  Library: View,
  Search: View,
  Study: View,
  Settings: View,
  Accessory: View
>: View {
  @Binding var selection: AppTab
  /// Gate the bottom accessory: the system draws the glass platter even for
  /// empty accessory content, so the modifier itself has to come and go to hide
  /// the chrome when nothing is playing.
  var showsAccessory: Bool
  @ViewBuilder var library: () -> Library
  @ViewBuilder var search: () -> Search
  @ViewBuilder var study: () -> Study
  @ViewBuilder var settings: () -> Settings
  @ViewBuilder var bottomAccessory: () -> Accessory

  var body: some View {
    TabView(selection: $selection) {
      Tab(value: AppTab.library) {
        library()
      } label: {
        Label("Library", systemImage: "music.note.list")
      }

      Tab(value: AppTab.search, role: .search) {
        search()
      } label: {
        Label("Search", systemImage: "magnifyingglass")
      }

      Tab(value: AppTab.study) {
        study()
      } label: {
        Label("Study", systemImage: "rectangle.on.rectangle.angled")
      }

      Tab(value: AppTab.settings) {
        settings()
      } label: {
        Label("Settings", systemImage: "gearshape")
      }
    }
    .modifier(BottomAccessoryModifier(isPresented: showsAccessory, accessory: bottomAccessory))
    // The global `AccentColor` asset doesn't drive the Liquid Glass tab bar's
    // selected-item tint on its own, so apply it explicitly here. Reading the
    // same `AccentColor` colorset keeps one source of truth (and its light/dark
    // P3 variants) while also tinting the controls nested in each tab —
    // Settings pickers, NavigationLink chevrons, the search field.
    .tint(Color("AccentColor"))
  }
}

/// Conditionally attaches `tabViewBottomAccessory`. Keeping this in a modifier
/// lets `body` return one concrete type while the accessory toggles on and off
/// with playback state.
private struct BottomAccessoryModifier<Accessory: View>: ViewModifier {
  let isPresented: Bool
  @ViewBuilder var accessory: () -> Accessory

  func body(content: Content) -> some View {
    if isPresented {
      content.tabViewBottomAccessory { accessory() }
    } else {
      content
    }
  }
}
