## Purpose

The iOS design system provides a layered UI foundation: a token layer of radii,
spacing, typography, motion, and material roles; a primitive layer of small
typed components composed from those tokens; and a chrome layer that owns the
tab bar, mini-player, and Now Playing surfaces through a single composition
root. A material contract splits glass roles, reserved for chrome with a
refractable backdrop, from opaque roles used wherever content needs maximum
legibility. An accessibility floor guarantees labeled controls, Dynamic Type
scaling, and graceful degradation under reduced transparency and reduced motion.

## Requirements

### Requirement: Token layer

The app SHALL expose design tokens under `DesignSystem/Tokens/` covering:

- `Radii` — `.sm`, `.md`, `.lg`, `.xl`, `.xxl` corner-radius steps.
- `Spacing` — 4-point grid steps `.xs`, `.s`, `.m`, `.l`, `.xl`, `.xxl`.
- `Typography` — `.pageTitle`, `.sectionTitle`, `.body`, `.metadata`,
  `.lyricActive`, `.lyricRest`, `.furigana`, all built on relative SwiftUI text
  styles so they scale with Dynamic Type.
- `Motion` — exactly three role-based animation presets: `.pop`, `.ease`,
  `.sheet`. Feature code SHALL pick a role rather than declaring bespoke spring
  or ease durations.
- `Materials` — split into glass roles (`chromeGlass`, `capsuleTier`,
  `controlTier`) and opaque roles (`contentSurface`, `popoverSurface`).

#### Scenario: Tokens are the single source of truth

- **WHEN** a feature view declares padding, corner radius, font, animation, or
  background material
- **THEN** it references a `Spacing`, `Radii`, `Typography`, `Motion`, or
  `Materials` token rather than a raw `CGFloat`, `Font.system(size:)`, or ad-hoc
  `Animation.spring(...)` call

#### Scenario: Motion budget is three roles

- **WHEN** a view animates a state change
- **THEN** the animation references `Motion.pop`, `Motion.ease`, or
  `Motion.sheet` — no bespoke `withAnimation(.spring(...))` calls

### Requirement: Primitive layer

The app SHALL expose composable primitives under `DesignSystem/Primitives/`:

- `Surface` — opaque content card; accepts only opaque `Material` tokens.
- `GlassChrome` — `.glassEffect()` rounded-rectangle wrapper; accepts only
  `Glass` role tokens.
- `GlassCapsule` — pill / chip wearing glass.
- `RowItem` — artwork + two-line text + optional trailing.
- `TransportButton` — transport with `.bounce` SymbolEffect choreography on tap
  and a `.scale` press-down response.
- `Scrubber` — drag-to-seek position bar with `.light` haptic detents at the 25
  / 50 / 75% points.
- `SectionHeader` — title row with optional trailing action.
- `EmptyState` — icon + title + body + optional action surface.

Each primitive SHALL be small, typed, and named after the product concept it
renders. Misuse SHALL fail at the call site (chrome cannot be hosted on a
content surface; opaque material cannot be passed to a glass wrapper).

#### Scenario: Glass cannot be hosted on Surface

- **WHEN** a developer attempts to pass `Materials.chromeGlass` to `Surface`
- **THEN** the call fails to compile — `Surface` only accepts `Material` tokens
  (opaque), never `Glass` roles

#### Scenario: Opaque material cannot be hosted on GlassChrome

- **WHEN** a developer attempts to pass `Materials.contentSurface` to
  `GlassChrome`
- **THEN** the call fails to compile — `GlassChrome` only accepts `Glass` role
  tokens

#### Scenario: Feature views compose primitives

- **WHEN** a new list / row / empty state / pill chip / transport control is
  added to the app
- **THEN** the implementation composes the corresponding primitive (`RowItem`,
  `EmptyState`, `GlassCapsule`, `TransportButton`, etc.) rather than declaring
  its own inline rendering

### Requirement: Chrome layer

The app SHALL expose chrome under `DesignSystem/Chrome/`:

- `LiquidGlassTabBar` — three-tab native `TabView` with Library, Search,
  Settings.
- `MiniPlayer` — collapsed-state row that sits above the tab bar via
  `tabViewBottomAccessory`.
- `NowPlayingSheet` — expanded-state full-height sheet with glass header and
  album-art backdrop.
- `NowPlayingContent` — the inner body rendered inside `NowPlayingSheet` (header
  chip, artwork, source chip, lyric column, scrubber, transport).
- `MiniPlayerExpansion` — observable state machine
  (`collapsed → expanding → expanded → collapsing → collapsed`) that guards the
  matched-geometry morph against rapid expand-collapse cycles.

`AppShell` SHALL be the single composition root for these surfaces. Feature
views SHALL NOT reach into the chrome layer directly — they communicate with the
player by calling `NowPlayingState.play(track:)` and (where relevant)
`MiniPlayerExpansion.requestExpand()` from the environment.

#### Scenario: AppShell owns the matched-geometry namespace

- **WHEN** the mini-player and NowPlayingSheet need to morph artwork / title /
  artist between collapsed and expanded states
- **THEN** they share a single `@Namespace` declared on `AppShell`; neither the
  mini-player nor the sheet creates its own namespace

#### Scenario: Feature views do not own chrome

- **WHEN** a feature view (Library, Search, Settings) wants to surface playback
  to the user
- **THEN** it calls `NowPlayingState.play(track:)` and
  `MiniPlayerExpansion.requestExpand()`; it does not declare a TabView, mount a
  mini-player, or present the NowPlayingSheet directly

### Requirement: Chrome vs content material contract

The app SHALL enforce a chrome-vs-content split:

| Surface                       | Material                            |
| ----------------------------- | ----------------------------------- |
| Tab bar                       | `Materials.chromeGlass`             |
| Mini-player                   | `Materials.chromeGlass`             |
| NowPlayingSheet header chrome | `Materials.chromeGlass`             |
| Provider chip, device chip    | `Materials.capsuleTier`             |
| Transport buttons (on chrome) | `Materials.controlTier`             |
| Search field (in Search tab)  | `Materials.chromeGlass`             |
| Settings form sections        | `Materials.contentSurface` (opaque) |
| Reading editor card (frame)   | `Materials.chromeGlass`             |
| Reading editor field inset    | `Materials.contentSurface` (opaque) |
| Dropdowns / menus             | `Materials.popoverSurface` (opaque) |
| Destructive confirms          | `Materials.popoverSurface` (opaque) |

Glass surfaces SHALL be reserved for chrome with a refractable backdrop. Opaque
surfaces SHALL be used wherever content needs maximum legibility (forms, dense
menus, safety-critical confirms).

#### Scenario: Settings stays on opaque material

- **WHEN** the Settings tab renders
- **THEN** the surrounding Form is opaque (`bar` / `contentSurface` material),
  and inline affordances such as the provider status chip wear `GlassCapsule`
  only because they're load-bearing pills, not because Settings opted into
  chrome

#### Scenario: Reading editor floats as glass with an opaque field inset

- **WHEN** the kanji reading editor is presented as a focus overlay over the
  lyric column
- **THEN** the card _frame_ wears `Materials.chromeGlass` (it floats over the
  refractable lyric backdrop), while the editable field sits on an opaque
  `Materials.contentSurface` inset so the kana stays legible

### Requirement: Accessibility floor

Every interactive element in the design-system primitives SHALL expose an
`accessibilityLabel`. The `Typography` token set SHALL use relative text styles
so all surfaces scale with Dynamic Type. `.glassEffect()` SHALL be relied upon
to fall back to opaque material under `accessibilityReduceTransparency`.
`matchedGeometryEffect` SHALL be relied upon to degrade to a cross-fade under
`accessibilityReduceMotion`.

#### Scenario: Transport buttons name their action

- **WHEN** VoiceOver focuses a `TransportButton`
- **THEN** the spoken label describes the action (e.g., "Play", "Pause", "Next
  track", "Previous track", "Up next") rather than a glyph name

#### Scenario: Lyric column scales with Dynamic Type

- **WHEN** the user enables an accessibility text size such as AX3
- **THEN** the lyric column renders at the scaled size with no clipping or
  truncation of the active line
