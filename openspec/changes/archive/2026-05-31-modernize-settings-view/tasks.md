## 1. Section container redesign

- [ ] 1.1 Rework `sectionCard(_:content:)` in `SettingsView.swift` from an inset
      `Surface(material: .contentSurface)` card to an edge-to-edge grouped
      section: full-width content on a faint opaque fill
      (`secondarySystemGroupedBackground` or equivalent semantic system fill),
      no horizontal `Spacing.l` inset on the container.
- [ ] 1.2 Add faint top/bottom hairline rules (`Color(.separator)` at low
      opacity) framing each section; keep internal padding via `Spacing` tokens
      so content does not touch the screen edges.
- [ ] 1.3 Where any rounding remains, move it to a softer step (`Radii.xl`); if
      the grouped sections go full-bleed square, remove the corner radius
      accordingly.
- [ ] 1.4 Insert inset hairline `Divider`s between multi-row content within a
      section (Appearance theme/language already has one — keep consistent).

## 2. Background & rhythm

- [ ] 2.1 Calm `backgroundBase`: keep it pure color (legible under Reduce
      Transparency) and soften the accent wash so the faint section fills read
      clearly against it.
- [ ] 2.2 Tune vertical spacing between sections and around the pinned hero
      title using `Spacing.l` / `Spacing.xl` for an airy grouped rhythm.

## 3. Preserve controls

- [ ] 3.1 Confirm the provider selector, theme selector, language menu,
      Customization navigation row, connect-error note, and Sign Out button are
      reused unchanged and render correctly inside the new section containers.

## 4. Spec sync

- [ ] 4.1 Apply the `design-system` material-contract delta to
      `openspec/specs/design-system/spec.md`: update the "Settings form
      sections" table row and the "Settings stays on opaque material" scenario
      to the edge-to-edge grouped opaque treatment.

## 5. Verify

- [ ] 5.1 Build the app and open Settings; confirm the strong white card look is
      gone and sections read as edge-to-edge grouped panels.
- [ ] 5.2 Verify legibility and separation in light mode, dark mode, and with
      Reduce Transparency enabled.
- [ ] 5.3 Verify Dynamic Type scaling and VoiceOver labels on the selectors and
      rows are unaffected.
