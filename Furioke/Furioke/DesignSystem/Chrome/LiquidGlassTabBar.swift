import SwiftUI

enum AppTab: Hashable {
  case library
  case search
  case settings
}

// Three-tab native iOS 26 TabView. The Liquid Glass treatment of the bar
// itself is provided by the system; this view is just the typed composition
// root that names the three destinations and hosts the persistent mini-player
// above the bar via `tabViewBottomAccessory`.

struct LiquidGlassTabBar<Library: View, Search: View, Settings: View, Accessory: View>: View {
  @Binding var selection: AppTab
  @ViewBuilder var library: () -> Library
  @ViewBuilder var search: () -> Search
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

      Tab(value: AppTab.settings) {
        settings()
      } label: {
        Label("Settings", systemImage: "gearshape")
      }
    }
    .tabViewBottomAccessory {
      bottomAccessory()
    }
    // The global `AccentColor` asset doesn't drive the Liquid Glass tab bar's
    // selected-item tint on its own, so apply it explicitly here. Reading the
    // same `AccentColor` colorset keeps one source of truth (and its light/dark
    // P3 variants) while also tinting the controls nested in each tab —
    // Settings pickers, NavigationLink chevrons, the search field.
    .tint(Color("AccentColor"))
  }
}
