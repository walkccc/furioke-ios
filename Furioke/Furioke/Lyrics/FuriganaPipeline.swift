import Foundation

/// One rendered segment of a lyric line: a kanji run carrying a reading, or a
/// plain run (kana / latin / punctuation) with `reading == nil`.
///
/// `wordSurface` / `wordReading` carry the *whole* word this cell was split from —
/// the kuromoji token (or matched correction span) before okurigana alignment. The
/// reading editor keys an override by `wordSurface`, not the per-cell kanji run,
/// because `CorrectionMap` only ever matches whole token spans: keying by a bare
/// kanji run (e.g. 続 out of 続く) would store a row that never matches on re-render.
nonisolated struct RubyToken: Equatable {
  let surface: String
  let reading: String?
  let wordSurface: String
  let wordReading: String
}

/// A single lyric line annotated for display. The annotated value lives only in
/// memory — the persisted form is the raw LRC body.
nonisolated struct AnnotatedLine: Equatable {
  /// Playback offset in ms for synced (LRC) lyrics; nil for plain lyrics.
  let timeMs: Int?
  // Plain line text with timestamps stripped — the input to the line hash.
  let text: String
  let tokens: [RubyToken]
  /// Hepburn rōmaji for the whole line, derived on-device from the readings
  /// (`Romaji`). Empty for blank lines. Rendered only when the rōmaji row is on.
  let romaji: String
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

  /// Parse the LRC body into display lines **without tokenizing** — instant, no
  /// furigana or rōmaji. Each non-blank line becomes a single plain `RubyToken`
  /// so the surface is readable immediately; `annotate` runs next and replaces
  /// these with ruby-annotated lines once the (cold) kuromoji build is ready.
  func plainLines(lrcBody: String) -> [AnnotatedLine] {
    Self.parseLines(lrcBody).map { line in
      let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
      let tokens = trimmed.isEmpty
        ? []
        : [RubyToken(surface: line.text, reading: nil, wordSurface: line.text, wordReading: line.text)]
      return AnnotatedLine(
        timeMs: line.timeMs,
        text: line.text,
        tokens: tokens,
        romaji: "",
        lineHash: LineHash.hash(line.text)
      )
    }
  }

  func annotate(lrcBody: String, corrections: CorrectionMap) async throws -> [AnnotatedLine] {
    let lines = Self.parseLines(lrcBody)
    var result: [AnnotatedLine] = []
    result.reserveCapacity(lines.count)
    for line in lines {
      let annotated = try await annotateLine(line.text, corrections: corrections)
      result.append(
        AnnotatedLine(
          timeMs: line.timeMs,
          text: line.text,
          tokens: annotated.tokens,
          romaji: annotated.romaji,
          lineHash: LineHash.hash(line.text)
        )
      )
    }
    return result
  }

  private func annotateLine(
    _ text: String,
    corrections: CorrectionMap
  ) async throws -> (tokens: [RubyToken], romaji: String) {
    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return ([], "") }

    let tokens = try await bridge.tokenize(text)
    let romaji = Self.romanize(tokens)
    let surfaces = tokens.map(\.surface)
    var out: [RubyToken] = []
    var i = 0
    while i < tokens.count {
      // A correction-map match wins over kuromoji's per-token reading and may
      // span several tokens (二 + 人).
      if let matched = corrections.match(surfaces: surfaces, at: i) {
        out.append(contentsOf: Self.align(surface: matched.surface, reading: matched.reading))
        i += matched.tokenCount
        continue
      }
      let token = tokens[i]
      if Self.containsKanji(token.surface), let reading = token.reading, !reading.isEmpty {
        out.append(contentsOf: Self.align(
          surface: token.surface,
          reading: Self.toHiragana(reading)
        ))
      } else {
        // A plain run (kana / latin / punctuation) is its own word and isn't
        // editable, so its word context is just itself.
        out.append(RubyToken(
          surface: token.surface,
          reading: nil,
          wordSurface: token.surface,
          wordReading: token.surface
        ))
      }
      i += 1
    }
    return (out, romaji)
  }

  // MARK: - Rōmaji

  /// Build a line's Hepburn rōmaji from kuromoji's word-level tokens: each kanji
  /// run romanizes from its reading, kana/latin from the surface, joined by
  /// spaces at word boundaries (`Romaji`). Word granularity comes from the
  /// tokenizer because the `RubyToken` stream has already been split at okurigana.
  private static func romanize(_ tokens: [KuromojiBridge.Token]) -> String {
    var words: [String] = []
    words.reserveCapacity(tokens.count)
    for token in tokens {
      let kana: String
      if containsKanji(token.surface), let reading = token.reading, !reading.isEmpty {
        kana = toHiragana(reading)
      } else {
        kana = toHiragana(token.surface)
      }
      let word = Romaji.fromKana(kana).trimmingCharacters(in: .whitespaces)
      if !word.isEmpty { words.append(word) }
    }
    return words.joined(separator: " ")
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
    surface.contains(where: isKanji)
  }

  private static func isKanji(_ character: Character) -> Bool {
    character.unicodeScalars.contains { scalar in
      (0x4E00 ... 0x9FAF).contains(scalar.value) || (0x3400 ... 0x4DBF).contains(scalar.value)
    }
  }

  // MARK: - Okurigana alignment

  /// Align kanji runs in base with corresponding spans of reading, using
  /// intervening okurigana kana as anchors. Falls back to a single ruby span
  /// when alignment is ambiguous.
  ///
  /// Examples:
  ///   "続く"   / "つづく"    → [ruby(続,つづ), text(く)]
  ///   "置き忘れ" / "おきわすれ" → [ruby(置,お), text(き), ruby(忘,わす), text(れ)]
  static func align(surface: String, reading: String) -> [RubyToken] {
    // The whole word — preserved on every produced cell so the reading editor can
    // key an override by it (see `RubyToken`), regardless of how the run is split.
    let wordSurface = surface
    let wordReading = reading
    let single = [RubyToken(
      surface: surface,
      reading: reading,
      wordSurface: wordSurface,
      wordReading: wordReading
    )]
    let segments = segment(surface)
    // A lone kanji run (二人 / ふたり) or a run with no okurigana to anchor on has
    // nothing to split against — keep the whole reading over the whole surface.
    guard segments.count > 1 else { return single }

    let reading = Array(reading)
    var cursor = 0
    var out: [RubyToken] = []
    out.reserveCapacity(segments.count)

    for (index, seg) in segments.enumerated() {
      if seg.isKanji {
        // The kanji run reads from the cursor up to the next kana anchor, or to
        // the end of the reading for a trailing kanji run. Search begins one
        // past the cursor so the run always claims at least one reading char.
        let anchor = index + 1 < segments.count ? Array(segments[index + 1].text) : []
        let end: Int
        if anchor.isEmpty {
          end = reading.count
        } else if let found = firstIndex(of: anchor, in: reading, from: cursor + 1) {
          end = found
        } else {
          return single // anchor missing in the reading → ambiguous
        }
        guard end > cursor else { return single }
        out.append(RubyToken(
          surface: seg.text,
          reading: String(reading[cursor ..< end]),
          wordSurface: wordSurface,
          wordReading: wordReading
        ))
        cursor = end
      } else {
        // A non-kanji run must appear verbatim at the cursor; okurigana reads as
        // itself, so any divergence means the reading and surface disagree.
        let kana = Array(seg.text)
        guard cursor + kana.count <= reading.count,
              Array(reading[cursor ..< cursor + kana.count]) == kana
        else {
          return single
        }
        out.append(RubyToken(
          surface: seg.text,
          reading: nil,
          wordSurface: wordSurface,
          wordReading: wordReading
        ))
        cursor += kana.count
      }
    }
    // Every reading character must be consumed; leftovers mean the split drifted.
    guard cursor == reading.count else { return single }
    return out
  }

  private struct Segment {
    let text: String
    let isKanji: Bool
  }

  /// Split a surface into maximal runs of kanji and non-kanji characters.
  private static func segment(_ surface: String) -> [Segment] {
    var segments: [Segment] = []
    var current = ""
    var currentIsKanji = false
    for character in surface {
      let kanji = isKanji(character)
      if current.isEmpty {
        current = String(character)
        currentIsKanji = kanji
      } else if kanji == currentIsKanji {
        current.append(character)
      } else {
        segments.append(Segment(text: current, isKanji: currentIsKanji))
        current = String(character)
        currentIsKanji = kanji
      }
    }
    if !current.isEmpty {
      segments.append(Segment(text: current, isKanji: currentIsKanji))
    }
    return segments
  }

  /// First index at or after `from` where `needle` occurs in `haystack`.
  private static func firstIndex(
    of needle: [Character],
    in haystack: [Character],
    from start: Int
  ) -> Int? {
    guard !needle.isEmpty, start >= 0 else { return nil }
    var i = start
    while i + needle.count <= haystack.count {
      if Array(haystack[i ..< i + needle.count]) == needle { return i }
      i += 1
    }
    return nil
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
