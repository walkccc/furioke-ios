import Foundation

/// A reading-correction map layered over kuromoji output, ported from the web's
/// `lib/lyrics/reading-corrections.ts`. kuromoji + IPADIC gives a token's
/// morphological reading, which is often not the sung reading for number+counter
/// and jukujikun compounds (e.g. 二人 as ににん rather than ふたり). The bundled
/// seed fixes known song-domain misreads for everyone; per-user overrides extend
/// it and take precedence.
///
/// Per-user overrides come from `OverrideEntity`, which lands in a later change.
/// To avoid coupling the annotator to a SwiftData model that does not exist yet,
/// the caller loads those overrides and passes them in — mirroring the web's
/// `setUserOverrides(map)` seam.
nonisolated struct CorrectionMap {
  struct Match: Equatable {
    let surface: String
    let reading: String
    let tokenCount: Int
  }

  private let entries: [String: String]
  /// Longest key length in UTF-16 code units, matching JS `String.length`
  /// semantics so the greedy-match cutoff behaves identically to the web.
  private let maxKeyLength: Int

  init(seed: [String: String], userOverrides: [String: String] = [:]) {
    var merged = seed
    for (surface, reading) in userOverrides {
      merged[surface] = reading
    }
    entries = merged
    maxKeyLength = merged.keys.map { $0.utf16.count }.max() ?? 0
  }

  /// The corrected reading for an exact surface, or nil when nothing maps it.
  func correction(for surface: String) -> String? {
    entries[surface]
  }

  /// Starting at `index`, find the longest run of consecutive token surfaces
  /// whose concatenation exactly matches a map key. This makes a mapped compound
  /// correct whether kuromoji emitted it whole or split it (二 + 人).
  func match(surfaces: [String], at index: Int) -> Match? {
    var surface = ""
    var best: Match?
    var j = index
    while j < surfaces.count {
      surface += surfaces[j]
      if surface.utf16.count > maxKeyLength { break }
      if let reading = entries[surface] {
        best = Match(surface: surface, reading: reading, tokenCount: j - index + 1)
      }
      j += 1
    }
    return best
  }
}

nonisolated extension CorrectionMap {
  /// The bundled seed shared with the web app (`lib/lyrics/seed.json`), vendored
  /// into the iOS bundle as `seed.json`.
  static func loadSeed() -> [String: String] {
    guard let url = Bundle.main.url(forResource: "seed", withExtension: "json")
      ?? Bundle.main.url(forResource: "seed", withExtension: "json", subdirectory: "Resources"),
      let data = try? Data(contentsOf: url),
      let map = try? JSONDecoder().decode([String: String].self, from: data)
    else {
      return [:]
    }
    return map
  }

  static func withSeed(userOverrides: [String: String] = [:]) -> CorrectionMap {
    CorrectionMap(seed: loadSeed(), userOverrides: userOverrides)
  }
}
