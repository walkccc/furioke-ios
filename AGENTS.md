# AGENTS.md

Design system, chrome, navigation, motion, and accessibility rules live in
[DESIGN.md](DESIGN.md). Read it before touching UI.

## Core Rules

- Never run Xcode CLI commands that compile the app (e.g. `xcodebuild`); never
  launch the iOS simulator.
- Write senior-level Swift 6 code under strict concurrency.
- Read only files relevant to the task; never blindly scan directories.

## Tech Stack

- Swift 6.0, strict concurrency, async/await, structured concurrency
- iOS 26.0, SwiftUI, SwiftData
- No MVVM; no view models by default

## State & Architecture

SwiftData is the source of truth.

- `@Model` is primary app state; domain logic lives in `@Model` extensions,
  model actors, or focused domain services.
- `@State` is for ephemeral UI state only. Views stay dumb.
- Fetch with `@Query`; inject dependencies via SwiftUI `Environment`.
- Never duplicate persisted state into view state; avoid global mutable state.

Prefer native SwiftUI/SwiftData patterns. Acceptable layers: models, model
extensions, model actors, design-system primitives, feature views, app-shell
composition.

Avoid: unnecessary coordinators, single-implementation protocols, premature
service layers, over-modeled state containers, deeply nested generic views.

## File Access

Before editing, read the target file, nearby siblings, the design-system
token/primitive in use, and the model involved — then stop. Don't open unrelated
files or scan large directories.

## Making Changes

- Match existing style; keep diffs minimal; prefer local fixes.
- Update types and initializers when changing data shape; keep styling on theme
  tokens.
- Preserve comments explaining non-obvious decisions; drop comments that just
  repeat code.
- Never silently change behavior, persistence models, or navigation flows.

When changing models, also update previews/sample data, consider migration
impact, and preserve existing data.

## Swift Style

Prefer value types, small focused views, clear names, async/await over
callbacks, and `@MainActor` only where needed.

Avoid: force unwraps, unstructured tasks without ownership, broad `@MainActor`
as a shortcut, unnecessary protocols or type erasure, massive view bodies,
hidden state synchronization.

## Concurrency

Follow Swift 6 strict concurrency. Don't silence errors with
`@unchecked Sendable` or `nonisolated(unsafe)` unless there is no safer design —
and then add a short explanation.

## Simplifying Code

Remove dead abstractions, collapse unnecessary layers, inline single-use helpers
when clearer, extract repeated patterns when useful, and prefer clear names over
comments. Keep the result boring and obvious. Don't introduce new architecture
while simplifying.

## Copy

Keep copy concise, warm, and product-like — calm, minimal, modern, helpful, not
noisy. Avoid corporate or overly cute tone.

## Response Style

Be concise. Summarize what changed, why, and what to verify locally, plus any
important architectural note. Never claim builds or tests passed unless the
developer ran them and reported the result.
