## MODIFIED Requirements

### Requirement: Chrome vs content material contract

The app SHALL enforce a chrome-vs-content split:

| Surface                       | Material                                   |
| ----------------------------- | ------------------------------------------ |
| Tab bar                       | `Materials.chromeGlass`                    |
| Mini-player                   | `Materials.chromeGlass`                    |
| NowPlayingSheet header chrome | `Materials.chromeGlass`                    |
| Provider chip, device chip    | `Materials.capsuleTier`                    |
| Transport buttons (on chrome) | `Materials.controlTier`                    |
| Search field (in Search tab)  | `Materials.chromeGlass`                    |
| Settings form sections        | Opaque grouped background, hairline-framed |
| Reading editor card (frame)   | `Materials.chromeGlass`                    |
| Reading editor field inset    | `Materials.contentSurface` (opaque)        |
| Dropdowns / menus             | `Materials.popoverSurface` (opaque)        |
| Destructive confirms          | `Materials.popoverSurface` (opaque)        |

Glass surfaces SHALL be reserved for chrome with a refractable backdrop. Opaque
surfaces SHALL be used wherever content needs maximum legibility (forms, dense
menus, safety-critical confirms).

Settings form sections SHALL render as an edge-to-edge grouped treatment —
full-width sections separated by spacing and framed by faint hairline rules —
rather than prominent inset bright-white cards. Sections SHALL sit flush on the
opaque grouped background (a semantic system color such as
`systemGroupedBackground`), which is the opaque legibility substrate, so they
read as continuous panels rather than stark white slabs while keeping the opaque
/ maximum-legibility guarantee. Settings SHALL NOT adopt glass material for its
content.

#### Scenario: Settings stays on opaque material

- **WHEN** the Settings tab renders
- **THEN** its sections sit flush on the opaque grouped background (never glass)
  and present as edge-to-edge grouped panels framed by hairline rules rather
  than inset bright-white cards, and inline affordances such as the provider
  status chip wear `GlassCapsule` only because they're load-bearing pills, not
  because Settings opted into chrome

#### Scenario: Reading editor floats as glass with an opaque field inset

- **WHEN** the kanji reading editor is presented as a focus overlay over the
  lyric column
- **THEN** the card _frame_ wears `Materials.chromeGlass` (it floats over the
  refractable lyric backdrop), while the editable field sits on an opaque
  `Materials.contentSurface` inset so the kana stays legible
