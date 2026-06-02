import SwiftUI

enum AppTab: Hashable {
  case library
  case search
  case tango
  case settings
}

// Four-tab native iOS 26 TabView. The Liquid Glass treatment of the bar
// itself is provided by the system; this view is just the typed composition
// root that names the destinations and hosts the persistent mini-player
// above the bar via `tabViewBottomAccessory`.

struct LiquidGlassTabBar<
  Library: View,
  Search: View,
  Tango: View,
  Settings: View,
  Accessory: View
>: View {
  @Binding var selection: AppTab
  /// Whether the bottom accessory is shown: true while a track is current (so it
  /// stays up through a pause), false when no provider/track is active. Drives the
  /// always-applied `tabViewBottomAccessory`'s `isEnabled:` flag (see
  /// `BottomAccessoryModifier`) rather than adding/removing the modifier, so the
  /// `TabView`'s identity never changes — toggling the modifier on/off used to tear
  /// down and rebuild every tab on first playback.
  var showsAccessory: Bool
  @ViewBuilder var library: () -> Library
  @ViewBuilder var search: () -> Search
  @ViewBuilder var tango: () -> Tango
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

      // The vocabulary deck. Localized per the app language: "Tango" (en),
      // "単語" (ja), "單字" (zh-Hant) — see `Localizable.xcstrings`.
      Tab(value: AppTab.tango) {
        tango()
      } label: {
        Label {
          Text("Tango")
        } icon: {
          Image(systemName: "rectangle.on.rectangle.angled")
        }
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

/// Always attaches `tabViewBottomAccessory`, toggling its visibility with the
/// built-in `isEnabled:` parameter rather than adding/removing the modifier itself.
/// This is deliberate on both counts:
///
/// - An `if isPresented { content.modifier } else { content }` swaps the `TabView`
///   between two `_ConditionalContent` branches, which SwiftUI treats as different
///   identities — so flipping the flag (e.g. when the first track starts from a
///   Tango play button) tore down and rebuilt the whole `TabView`, resetting every
///   tab's `@State`, scroll, and navigation.
/// - Keeping the modifier applied but gating only its *content* (returning empty
///   when nothing plays) left the system drawing an empty glass platter.
///
/// `isEnabled: false` hides the platter *and* reclaims its space while leaving the
/// modifier — and thus the `TabView`'s identity — in place, so paused playback still
/// shows the bar (the track is still current) and an idle app with no active
/// provider shows nothing.
///
/// The `isEnabled:` overload only exists on iOS 26.1+, so on 26.0 we can't toggle
/// the native accessory without hitting one of the two trade-offs above. Instead
/// the 26.0 path floats our own glass mini-player above the tab bar with
/// `safeAreaInset` — the classic pre-`tabViewBottomAccessory` idiom — keeping the
/// inset always applied (so the `TabView`'s identity never changes) and gating only
/// its visibility. Because `MiniPlayer` leaves its own glass to the host, the 26.0
/// platter supplies the `chromeGlass` backdrop the native accessory would have.
private struct BottomAccessoryModifier<Accessory: View>: ViewModifier {
  let isPresented: Bool
  @ViewBuilder var accessory: () -> Accessory

  func body(content: Content) -> some View {
    if #available(iOS 26.1, *) {
      content.tabViewBottomAccessory(isEnabled: isPresented) {
        accessory()
      }
    } else {
      content.safeAreaInset(edge: .bottom, spacing: 0) {
        GlassChrome(role: Materials.chromeGlass, in: Capsule()) {
          accessory()
        }
        .padding(.horizontal, Spacing.m)
        .padding(.bottom, Spacing.xs)
        // The inset stays mounted; visibility (and its reserved space) is gated
        // so toggling `isPresented` neither rebuilds the `TabView` nor leaves an
        // empty platter behind.
        .frame(height: isPresented ? nil : 0, alignment: .bottom)
        .opacity(isPresented ? 1 : 0)
        .clipped()
        .allowsHitTesting(isPresented)
        .accessibilityHidden(!isPresented)
        .animation(Motion.pop, value: isPresented)
      }
    }
  }
}
