# AGENTS.md

## Core Principles

- Never run `xcodebuild`!
- Simplicity first.
- Fix root causes, not symptoms.
- Senior-level Swift 6 code only.
- Zesty, minimal, modern design — theme tokens live in
  `Shared/Enums/AppTheme.swift`.

## Bash command style

Avoid compound shell commands that combine `cd`, `&&`, `;`, pipes, or output
redirection.

Assume the session starts from the repo root.

Prefer Claude Code's Read, Grep, and Glob tools for inspecting files.

For Bash inspection, use separate simple commands instead of one compound
command.

Good:

- pwd
- sed -n '1,60p' lib/api/with-auth.ts
- grep -n "api.spotify.com\|/search\|q=\|type=track\|limit"
  lib/music/spotify-source.ts
- head -20 some-output-file

Avoid:

- cd /path && command
- command 2>/dev/null
- command1; command2
- command1 | command2

## Tech Stack

- Swift 6.0 (Strict Concurrency)
- iOS 26.0
- SwiftUI, SwiftData (NO MVVM), Async/Await
- Business logic lives in `@Model` extensions or Model Actors
- Views are dumb

State rules:

- `@Model` → primary state
- `@State` → ephemeral UI only
- Data fetching via `@Query`
- Dependencies via SwiftUI `Environment`

### Web counterpart

The web app lives at `../furioke`. You MAY read it when cross-referencing
behavior or design parity between iOS and web — the same access rules apply:
only files relevant to the task, never a blind scan, and ask first if unsure.

## Design System

The iOS app mirrors the web's chrome-vs-content discipline using native iOS 26
APIs (`.glassEffect()`, `GlassEffectContainer`, `tabViewBottomAccessory`,
`matchedGeometryEffect`). The layer lives under `Furioke/Furioke/DesignSystem/`.

### Layers

- **Tokens** (`DesignSystem/Tokens/`): `Radii`, `Spacing`, `Typography`,
  `Motion`, `Materials`. Feature code references these rather than declaring raw
  `CGFloat` literals, `Font.system(size:)`, or ad-hoc `Animation.spring(...)`
  calls. `Materials` is split into glass roles (`chromeGlass`, `capsuleTier`,
  `controlTier`) and opaque materials (`contentSurface`, `popoverSurface`).
- **Primitives** (`DesignSystem/Primitives/`): `Surface` (opaque content card),
  `GlassChrome` (glass wrapper), `GlassCapsule` (pill chip), `RowItem`,
  `TransportButton`, `Scrubber`, `SectionHeader`, `EmptyState`. The `Surface` /
  `GlassChrome` split is load-bearing — `Surface` only accepts opaque `Material`
  tokens and `GlassChrome` only accepts `Glass` role tokens. Misuse fails at the
  call site.
- **Chrome** (`DesignSystem/Chrome/`): `LiquidGlassTabBar`, `MiniPlayer`,
  `NowPlayingSheet`, `NowPlayingContent`, `MiniPlayerExpansion`. Composed inside
  `App/AppShell.swift`, which is the single root that knows about the tab bar +
  mini-player + sheet layout. Feature views never reach in.

### Chrome vs Content Surfaces

Same rule the web app holds itself to:

| Surface                       | Material                            |
| ----------------------------- | ----------------------------------- |
| Tab bar                       | `Materials.chromeGlass`             |
| Mini-player                   | `Materials.chromeGlass`             |
| NowPlayingSheet header chrome | `Materials.chromeGlass`             |
| Provider chip, device chip    | `Materials.capsuleTier`             |
| Transport buttons (on chrome) | `Materials.controlTier`             |
| Settings form sections        | `Materials.contentSurface` (opaque) |
| Override editor sheet         | `Materials.contentSurface` (opaque) |
| Dropdowns / menus             | `Materials.popoverSurface` (opaque) |
| Destructive confirms          | `Materials.popoverSurface` (opaque) |

Glass refracts what's behind it. Use it on chrome with a refractable backdrop
(tab bar, mini-player, sheet header, capsules). Use opaque material on content
that needs maximum legibility (Form, override editor, confirmation dialogs).

### Navigation IA

Three tabs: **Library**, **Search**, **Settings**. **Library** is the default on
launch. NowPlaying is not a tab — it is the expanded state of the persistent
`MiniPlayer` above the tab bar. Tapping a song in Library or Search plays the
track _and_ calls `MiniPlayerExpansion.requestExpand()` so the NowPlayingSheet
animates in via the matched-geometry namespace owned by `AppShell`.

### Motion Budget

Three roles, no others:

- `Motion.pop` — transport tap feedback, button presses, active-line scale.
- `Motion.ease` — incidental state transitions (selection, hint dismiss).
- `Motion.sheet` — mini-player expansion, sheet presentation.

Feature code never writes `withAnimation(.spring(...))` — it picks one of those
three roles.

### Accessibility Floor

- Every interactive element (button, capsule, transport, scrubber) carries an
  `accessibilityLabel`. The shared `TransportButton` exposes one by construction
  so callers cannot forget it.
- `Typography` tokens use relative text styles, so every surface scales with
  Dynamic Type out of the box.
- `.glassEffect()` falls back to opaque material under
  `accessibilityReduceTransparency` automatically.
- `matchedGeometryEffect` degrades to a cross-fade under
  `accessibilityReduceMotion` automatically.

## Agent Behavior

### Builds

**Do not run `xcodebuild`** from agent tool calls. iOS builds and tests take
several minutes per invocation and are best run by the developer locally. Write
the Swift change, mention what to verify, and stop — the developer will run
`xcodebuild` (or hit ⌘B / ⌘U in Xcode) and report back. The same applies to
launching the iOS simulator, running schemes, or any other Xcode CLI that
compiles the iOS target.

### When making changes

- Read nearby files before editing (within the
  [access rules](#file-access-rules-critical)).
- Match existing project conventions.
- Prefer small, safe changes.
- Explain important architectural decisions briefly.
- Do not silently introduce new dependencies.
- Do not change unrelated behavior.
- Do not remove comments that explain non-obvious decisions.
- Update types when changing data shape.
- Keep styling consistent with existing theme tokens.
- Preserve user-facing copy unless asked to improve it.

### When asked to simplify code

- Remove dead abstractions.
- Collapse unnecessary layers.
- Extract repeated UI patterns.
- Prefer clear names over comments.
- Replace complex conditionals with readable helpers.
- Keep the final code boring and obvious.

### When asked to improve UI

- Improve spacing, hierarchy, alignment, states, and responsiveness first.
- Use color and animation second.
- Do not redesign the whole page unless requested.
- Preserve layout constraints when explicitly instructed.
