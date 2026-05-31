## Context

`SettingsView` renders four sections (Music, Appearance, Customization, Account)
through a single `sectionCard(_:content:)` helper: a `SectionHeader` over a
`Surface(material: .contentSurface, cornerRadius: .lg)` inset by `Spacing.l` on
each side. `contentSurface` resolves to `Color(.systemBackground)` — pure white
in light mode — so each section is a flat, hard-edged bright slab floating on
`systemGroupedBackground`. The lack of depth and the strong white contrast make
the screen read like leftover stock-`Form` chrome.

The design-system material contract (`openspec/specs/design-system/spec.md`)
pins "Settings form sections" to `Materials.contentSurface (opaque)` and
requires Settings to stay on opaque material for legibility. Any redesign must
keep Settings opaque — glass is reserved for chrome — so the fix is about
framing and tone, not switching to a translucent surface.

## Goals / Non-Goals

**Goals:**

- Remove the harsh floating bright-white card look the user objected to.
- Adopt an edge-to-edge grouped treatment: full-width sections, hairline rules,
  airy spacing, content reading as continuous panels.
- Keep every section on an opaque, maximally legible fill (material contract).
- Reuse all existing controls (provider/theme selectors, language menu,
  Customization row, Sign Out) unchanged — only the container chrome changes.
- Stay within existing design tokens (`Spacing`, `Radii`, `Typography`,
  `Materials`, `Motion`); no raw magic numbers in feature code.

**Non-Goals:**

- No change to Settings behavior, data flow, or provider connect/disconnect
  logic.
- No new global elevation/shadow token and no app-wide restyling — this change
  is scoped to Settings. (Other `Surface` users — `StudyView`,
  `ReadingEditorCard` — are untouched.)
- No switch to translucent / glass material for Settings content.

## Decisions

### Decision: Edge-to-edge grouped sections instead of inset bright cards

Replace the inset `Surface` card with a full-bleed section: the section content
spans the screen width (no `Spacing.l` horizontal inset on the card), separated
from its neighbors by vertical spacing and framed by faint top/bottom hairline
rules (`Color(.separator)` at low opacity). Within a section, multi-row content
is divided by inset hairline `Divider`s rather than packed into a slab.

**Why over alternatives:**

- _Soft elevated card (shadow + hairline, keep white):_ still a bright slab,
  just lifted — does not address the "strong white" complaint head-on.
- _Tinted material card:_ warmer, but tinting an opaque content surface risks
  drifting toward a non-token ad-hoc color and still keeps the boxed-card
  metaphor. Rejected to keep the screen minimal and airy.
- Edge-to-edge grouped reads as the app's own quiet design language, removes the
  floating-slab contrast entirely, and is the direction the user picked.

### Decision: Faint opaque fill, flush with the background

Each section sits on a faint opaque fill a hair off the base tone (e.g.
`Color(.secondarySystemGroupedBackground)` on a `systemGroupedBackground` base,
or a low-opacity neutral fill), rather than stark `systemBackground` white. This
keeps the opaque / maximum-legibility guarantee of the material contract while
eliminating the harsh white-on-gray contrast. The fill is nearly flush so
sections read as gentle panels, not bright cards.

**Why over alternatives:** painting sections directly on the bare background
(zero fill) would lose the legible opaque substrate the contract requires for
forms; a hair of opaque fill keeps content legible under Reduce Transparency
while staying subtle.

### Decision: Keep the helper-based structure and all controls

`sectionCard(_:content:)` stays the single section primitive — only its
container chrome (inset card → edge-to-edge grouped fill + rules) changes, so
every call site (`musicSection`, `appearanceSection`, `customizationSection`,
`accountSection`) and every inner control is reused verbatim. The corner radius
moves to a softer step (`Radii.xl`) where rounding remains, and the background
wash is calmed.

### Decision: Update the design-system material contract delta

Because the contract table explicitly lists "Settings form sections →
`Materials.contentSurface` (opaque)" with a "Settings stays on opaque material"
scenario, the redesign modifies that requirement. The delta keeps the opaque /
legibility floor and the glass-is-for-chrome rule but updates the Settings row
and scenario to describe the edge-to-edge grouped opaque treatment instead of
prominent inset cards.

## Risks / Trade-offs

- **[Lower contrast may reduce section separation]** → Faint top/bottom hairline
  rules plus generous `Spacing.l`/`Spacing.xl` vertical rhythm keep sections
  distinct without bright slabs.
- **[Reduce Transparency / dark mode legibility]** → The fill is pure opaque
  color (no glass), and the background wash stays pure color, so legibility
  holds under `accessibilityReduceTransparency` and in dark mode; verify both.
- **[Drifting from token discipline]** → Use system semantic colors
  (`secondarySystemGroupedBackground`, `separator`) and existing `Spacing` /
  `Radii` tokens; avoid hand-picked hex values so the change stays within the
  token-as-single-source-of-truth requirement.
- **[Inconsistency with other `Surface` screens]** → Scope is intentionally
  Settings-only; `StudyView` and `ReadingEditorCard` keep their card look. If
  this direction is later adopted app-wide, that is a separate change.
