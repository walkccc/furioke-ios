## Why

The Settings screen renders each section as an inset `Surface` card on
`Materials.contentSurface` — pure `systemBackground` (stark white in light mode)
floating on a gray grouped background. Flat, hard-edged, full-brightness slabs
read as leftover stock-`Form` chrome rather than the app's design language, and
the strong white contrast feels harsh. We want Settings to look deliberately
designed and modern without sacrificing the legibility the material contract
guarantees.

## What Changes

- Replace the inset bright-white section cards with an **edge-to-edge grouped**
  treatment: full-width sections separated by spacing and hairline rules, so
  content reads as continuous airy panels rather than bright floating slabs.
- Settings sections sit on a **faint opaque fill** that is nearly flush with the
  background (a hair off the base, not stark white), preserving the opaque /
  maximum-legibility guarantee while removing the harsh contrast.
- Soften the screen: calmer background wash, hairline separators between rows
  inside a group, and generous vertical rhythm.
- Keep the existing three-column provider / theme selectors, the language menu,
  the Customization navigation row, and the Sign Out action intact — only their
  container chrome changes.
- Update the design-system material contract so the Settings row reflects the
  edge-to-edge grouped opaque treatment (still opaque, still legible) instead of
  prominent inset `contentSurface` cards.

## Capabilities

### New Capabilities

_None — this is a visual refinement of an existing surface._

### Modified Capabilities

- `design-system`: The chrome-vs-content material contract for **Settings form
  sections** changes from prominent inset `Materials.contentSurface` cards to an
  edge-to-edge grouped opaque treatment. The opaque / maximum-legibility floor
  for Settings is unchanged; only the card framing is updated.

## Impact

- `Furioke/Furioke/Features/SettingsView.swift` — section container rendering
  (`sectionCard`), background, and separators. Selector cells, rows, and actions
  are reused unchanged.
- `openspec/specs/design-system/spec.md` — material-contract table row and the
  "Settings stays on opaque material" scenario.
- No changes to `AuthService`, `MusicState`, `PreferencesState`, or any data /
  provider behavior. Purely presentational.
