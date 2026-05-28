import Foundation

/// One rendered segment of a lyric line: a kanji run carrying a reading, or a
/// plain run (kana / latin / punctuation) with `reading == nil`.
nonisolated struct RubyToken: Equatable {
  let surface: String
  let reading: String?
}

/// A single lyric line annotated for display. The annotated value lives only in
/// memory — the persisted form is the raw LRC body (see [[ios-offline-cache]]).
nonisolated struct AnnotatedLine: Equatable {
  /// Playback offset in ms for synced (LRC) lyrics; nil for plain lyrics.
  let timeMs: Int?
  // Plain line text with timestamps stripped — the input to the line hash.
  let text: String
  let tokens: [RubyToken]
  let lineHash: String
}

/// Turns a raw LRC (or plain) lyric body into annotated lines, mirroring the
/// web's `generateFurigana` over `parseLrc` output. Tokenization runs through the
/// shared kuromoji bridge; corrections and reading conversion match the web's
/// `use-furigana.ts` exactly so both clients render identical readings.
nonisolated struct FuriganaPipeline {
  private let bridge: KuromojiBridge

  init(bridge: KuromojiBridge = .shared) {
    self.bridge = bridge
  }

  func annotate(lrcBody: String, corrections: CorrectionMap) async throws -> [AnnotatedLine] {
    let lines = Self.parseLines(lrcBody)
    var result: [AnnotatedLine] = []
    result.reserveCapacity(lines.count)
    for line in lines {
      let tokens = try await annotateLine(line.text, corrections: corrections)
      result.append(
        AnnotatedLine(
          timeMs: line.timeMs,
          text: line.text,
          tokens: tokens,
          lineHash: LineHash.hash(line.text)
        )
      )
    }
    return result
  }

  private func annotateLine(
    _ text: String,
    corrections: CorrectionMap
  ) async throws -> [RubyToken] {
    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [] }

    let tokens = try await bridge.tokenize(text)
    let surfaces = tokens.map(\.surface)
    var out: [RubyToken] = []
    var i = 0
    while i < tokens.count {
      // A correction-map match wins over kuromoji's per-token reading and may
      // span several tokens (二 + 人).
      if let matched = corrections.match(surfaces: surfaces, at: i) {
        out.append(RubyToken(surface: matched.surface, reading: matched.reading))
        i += matched.tokenCount
        continue
      }
      let token = tokens[i]
      if Self.containsKanji(token.surface), let reading = token.reading, !reading.isEmpty {
        out.append(RubyToken(surface: token.surface, reading: Self.toHiragana(reading)))
      } else {
        out.append(RubyToken(surface: token.surface, reading: nil))
      }
      i += 1
    }
    return out
  }

  // MARK: - LRC parsing

  private struct ParsedLine {
    let timeMs: Int?
    let text: String
  }

  /// Mirror of the web's `STAMP_RE` in `lib/music/lyric-sync.ts`.
  private static let stampRegex = try! NSRegularExpression(
    pattern: #"\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]"#
  )

  /// Synced LRC lines first (time-ordered, one entry per timestamp); if the body
  /// carries no timestamps, fall back to plain lines in document order.
  private static func parseLines(_ body: String) -> [ParsedLine] {
    let synced = parseSynced(body)
    if !synced.isEmpty { return synced }
    return body
      .split(separator: "\n", omittingEmptySubsequences: false)
      .map { ParsedLine(timeMs: nil, text: String($0)) }
  }

  private static func parseSynced(_ lrc: String) -> [ParsedLine] {
    var entries: [(ms: Int, text: String)] = []
    for raw in lrc.split(separator: "\n", omittingEmptySubsequences: false) {
      let line = String(raw)
      let ns = line as NSString
      let matches = stampRegex.matches(in: line, range: NSRange(location: 0, length: ns.length))
      if matches.isEmpty { continue }

      var stamps: [Int] = []
      var textStart = 0
      for match in matches {
        let minutes = Int(ns.substring(with: match.range(at: 1))) ?? 0
        let seconds = Int(ns.substring(with: match.range(at: 2))) ?? 0
        var fraction = 0
        let fractionRange = match.range(at: 3)
        if fractionRange.location != NSNotFound {
          let digits = ns.substring(with: fractionRange)
          fraction = Int(digits.padding(toLength: 3, withPad: "0", startingAt: 0)) ?? 0
        }
        stamps.append(minutes * 60_000 + seconds * 1_000 + fraction)
        textStart = match.range.location + match.range.length
      }

      let text = ns.substring(from: textStart).trimmingCharacters(in: .whitespacesAndNewlines)
      for ms in stamps {
        entries.append((ms, text))
      }
    }
    return entries
      .sorted { $0.ms < $1.ms }
      .map { ParsedLine(timeMs: $0.ms, text: $0.text) }
  }

  // MARK: - Reading helpers (ports of `use-furigana.ts`)

  /// CJK Unified Ideographs (U+4E00–U+9FAF) plus Extension-A (U+3400–U+4DBF),
  /// matching the web's `KANJI_RE`. Kana does not count.
  private static func containsKanji(_ surface: String) -> Bool {
    surface.unicodeScalars.contains { scalar in
      (0x4E00 ... 0x9FAF).contains(scalar.value) || (0x3400 ... 0x4DBF).contains(scalar.value)
    }
  }

  /// Katakana → hiragana by the same code-point shift the web uses: any scalar in
  /// U+30A0–U+30FF maps down by 0x60; everything else passes through.
  private static func toHiragana(_ katakana: String) -> String {
    let shifted = katakana.unicodeScalars.map { scalar -> Unicode.Scalar in
      if scalar.value >= 0x30A0, scalar.value <= 0x30FF {
        return Unicode.Scalar(scalar.value - 0x60)!
      }
      return scalar
    }
    return String(String.UnicodeScalarView(shifted))
  }
}
