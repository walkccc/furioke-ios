## Context

`Furioke/Features/SettingsView.swift` is the Settings tab. Today it pins a
custom rounded hero title ("Settings") above a stock grouped `Form` with four
sections: Appearance (theme + language `Picker`s), Music (provider `Picker`, a
connected `Label`, and Connect/Disconnect buttons with inline error text),
Customization (a `NavigationLink` to `ReadingOverridesView`), and a Sign Out
destructive button. It works and the interactions are correct, but visually it
is generic iOS while Now Playing and the just-redesigned Library speak a bespoke
Liquid Glass language (rounded display type, `Surface` cards, `GlassCapsule`
chips, tokens, the sage accent now present as `AccentColor`).

Every ingredient this redesign needs already exists in the design system:
`Surface` (opaque content card, `Radii.lg`), `SectionHeader` (rounded title +
trailing slot), `GlassCapsule` (glass chip), `EmptyState`, and the
`Typography`/`Spacing`/`Radii`/`Materials`/`Motion` tokens. The state layer is
untouched: `PreferencesState` (theme/language + `UserDefaults` persistence),
`MusicState` (`availableProviders`, `activeProvider`, `isConnected`, `select`,
`connect`, `disconnect`), and `AuthService.signOut()` are all consumed exactly
as today. The `providerSelection` binding's switch-tear-down-and-eager-connect
logic (Apple Music connects on selection, Spotify stays manual) is load-bearing
and must be preserved verbatim.

## Goals / Non-Goals

**Goals:**

- Make Settings fluent in the existing design language with no new aesthetic
  invented — reuse `Surface`, `SectionHeader`, `GlassCapsule`, tokens, and the
  sage `AccentColor`.
- Replace the grouped `Form` with a composed `ScrollView` of `Surface`-backed
  section cards under the existing pinned hero title.
- Turn the two most "stock" controls into visual, on-brand affordances: a theme
  selector (three selectable glyph cards) and a provider picker (selectable
  chips) with an explicit connection-state badge and one prominent action.
- Keep every interaction behavior identical — selection, eager Apple Music
  connect, connect/disconnect, error surfacing, navigation, sign out.

**Non-Goals:**

- No new design-system primitives. Selectors are private subviews of
  `SettingsView` composing existing primitives; the `design-system` spec is
  unchanged.
- No change to theme/language persistence, auth, or music connect/disconnect
  _behavior_ (those stay specified in `app-shell`, `auth`, `music-source`).
- No `ArtworkBackdrop` ambient wash here (see Decisions) — Settings has no
  single artwork subject and is a content surface that wants maximum legibility.
- No new settings (no new preferences, no provider logos/brand assets, no
  account details beyond the existing Sign Out).

## Decisions

### Decision: Composed `ScrollView` of `Surface` cards (not a styled `Form`)

Replace `Form { Section {...} }` with a
`ScrollView { VStack(spacing: Spacing.l) {...} }` where each group is a
`SectionHeader("…")` followed by a
`Surface(material: .contentSurface, cornerRadius: Radii.lg)` wrapping that
section's rows (`padding(Spacing.l)`), inside the existing outer horizontal
padding. The pinned hero title stays exactly as-is above the scroll.

_Why over alternatives:_ heavily restyling a `Form` (custom row backgrounds,
`scrollContentBackground(.hidden)`, `listRowInsets`) fights the system grouped
chrome and still leaks `Form` idioms (insets, separators, picker chevrons). A
`ScrollView` of `Surface` cards is the same composition Now Playing and the
design-system spec's "feature views compose primitives" rule already endorse,
and it gives full control over the visual treatment. The trade-off — losing
`Form`'s free keyboard avoidance and cell styling — is irrelevant here (no text
entry; the controls are taps/menus).

### Decision: Subtle brand-tinted background base (not `ArtworkBackdrop`)

The scroll sits over a quiet base — `Color(.systemGroupedBackground)` with an
optional very-soft sage tint derived from `AccentColor` — rather than the
`ArtworkBackdrop` ambient album-art wash that Library and Now Playing use.

_Why over alternatives:_ `ArtworkBackdrop` is seeded from a specific song's
artwork; Settings has no such subject (seeding from the now-playing track would
be arbitrary and would "pop" as playback changes). Settings is also a content
surface where the chrome-vs-content rule wants forms maximally legible, so an
opaque, low-contrast base under opaque `Surface` cards is the correct register.
Keeping it close to `systemGroupedBackground` also preserves the seamless strip
behind the pinned hero title that the current code is careful about.

### Decision: Theme as a selectable glyph-card row (not a `Picker`)

Render the three `ThemePreference` cases as a horizontal row of equal-width
selectable cards, each a glyph + label (System → `circle.lefthalf.filled`, Light
→ `sun.max`, Dark → `moon.stars` / `moon`). The selected card is filled/tinted
with `AccentColor` and carries a non-color indicator (filled state + a checkmark
or bolded label) so selection survives color-blindness and grayscale. Tapping a
card sets `preferences.theme` inside `withAnimation(Motion.pop)`.

_Why over alternatives:_ a segmented `Picker` is the low-effort option but reads
as stock iOS — exactly what we're moving away from. Visual cards are a common,
legible modern-settings idiom, reuse the accent, and make the appearance choice
feel tactile. The accent-only highlight risks failing color-only accessibility,
hence the paired non-color indicator (called out in the spec).

### Decision: Language stays a compact inline control

Language has four options including non-Latin labels; cards would crowd. Keep it
as a single labeled row whose trailing control is a `Menu` (or inline `Picker`
in `.menu` style) showing the current `LanguagePreference.label`. This keeps the
section visually calm and the change scoped to the high-value theme selector.

_Why:_ spending the visual budget where it counts (theme) and keeping language
compact avoids a busy section; the menu still reads cleanly inside a `Surface`.

### Decision: Provider grid where tapping connects (no badge, no connect/disconnect)

_Revised per feedback._ Replace the provider `Picker` + `Label` + buttons with a
three-column grid that **shares the theme selector's `optionCard`** — each
column is the provider's brand icon + name. The grid is fully self-contained:

- A column is highlighted **only while that provider is connected**
  (`activeProvider == provider && isConnected`); when nothing is connected,
  nothing is highlighted. The highlight _is_ the connection-state readout, so
  the separate `GlassCapsule` "Connected / Not connected" badge is removed.
- **Tapping a provider selects and connects it directly.** There is no separate
  Connect/Disconnect control. The tap clears the error, calls
  `music.select(provider)` (a no-op when already active — so a tap on a
  selected-but-disconnected provider just retries), then
  `connectActiveProvider()`. Tapping the already-connected provider is a no-op.
- The tapped column shows a `ProgressView` while connecting; a connect failure
  surfaces `error.userMessage` as a `Typography.metadata` caption below the
  grid.

This drops the eager-connect-only-for-Apple-Music distinction (now every
provider connects on tap) and removes explicit disconnect — switching providers
already tears the previous adapter down, so a dedicated disconnect control is
unnecessary.

The brand icons (Spotify, Apple Music, YouTube) are added to `Assets.xcassets`
as vector imagesets, traced from the web app's `components/furioke/icons/*.tsx`
SVG paths. These are folder additions inside the catalog, so no `.pbxproj` edit
is needed (consistent with the project's "no project-file edits" convention).

_Why over alternatives:_ the stock `Picker` hid providers behind a disclosure
and split connection state across a badge + a meaning-changing button. A single
grid where the highlight means "connected" and a tap means "connect" collapses
select, connect, and status into one glanceable, minimal control — the explicit
ask. The trade-off is the loss of a dedicated disconnect affordance (acceptable:
provider switching tears down the old adapter) and reliance on the connecting
`ProgressView`

- failure caption for feedback instead of a disabled button.

_Risk — asset-catalog SVG fidelity:_ Xcode's SVG importer supports a subset of
SVG; the Apple Music icon uses a `linearGradient` that may not render. If it
doesn't, fall back to a solid `#FA233B` fill. Verify on-device (task 5.1).

### Decision: Customization + Sign Out as explicit card rows

Reading Overrides becomes a `NavigationLink` styled as a card row: leading
`character.book.closed` glyph, title, trailing chevron — wrapped in/over a
`Surface`. Sign Out becomes a distinct full-width destructive control in its own
`Surface` card, visually separated from the rest. Both keep their current
destinations/actions (`ReadingOverridesView`, `AuthService.signOut()`).

_Why:_ preserves the navigation/auth behavior while giving these two rows the
same card vocabulary as the rest, so nothing reads as leftover `Form` chrome.

### Decision: Keep `NavigationStack` and the pinned hero

The Customization row pushes `ReadingOverridesView`, so the `NavigationStack`
and `.toolbar(.hidden, for: .navigationBar)` stay. The hero title keeps its
current top offset (safe area + `Spacing.l`) and the background extends behind
it so the strip above the first card doesn't read as a seam — the same care the
current code takes.

_Why:_ navigation is still required (unlike Library, which dropped its stack),
and matching the Library hero offset keeps the two tabs consistent.

## Risks / Trade-offs

- **Color-only selection state** → pair every accent-tinted selected state
  (theme cards, provider chips) with a non-color indicator (checkmark / filled /
  bold) and verify in grayscale; called out as a normative requirement in the
  spec.
- **Legibility of accent fills in both appearances** → `AccentColor` already
  ships light + dark variants; verify selected-card and chip contrast (text on
  accent fill) in both, and under Reduce Transparency where glass collapses to
  opaque material.
- **Dropping `Form` loses free behaviors** → no text entry here, so keyboard
  avoidance is moot; `ScrollView` + `contentMargins`/safe area must still clear
  the floating mini-player + tab bar (same `tabViewBottomAccessory` clearance
  Library relies on) — verify the last card isn't occluded.
- **Provider-switch logic regressing** → the eager-Apple-Music-connect and
  single-tear-down behavior is subtle; lift the existing `providerSelection`
  closure body verbatim into the chip tap rather than re-deriving it, and verify
  selecting Apple Music brings observation live while Spotify stays manual.
- **Dynamic Type / narrow widths** → theme cards and provider chips are
  horizontal; ensure they wrap or scale (or scroll) at large text sizes without
  clipping labels, especially the non-Latin language label and longer provider
  names.
- **Background-tint seam behind the hero** → if the tint isn't applied behind
  the pinned title too, the strip above the first card reads as a seam (the
  current code already guards this); extend the same base behind the hero.

## Open Questions

- Theme cards horizontal-equal-width vs. a vertical list at large Dynamic Type —
  prefer equal-width with graceful wrap/scale; confirm on-device.
- Whether provider chips should also surface a tiny per-provider glyph; deferred
  — no brand assets in scope, so text-only chips unless a neutral SF Symbol
  reads well.
