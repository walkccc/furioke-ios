import Foundation

/// Encodes and decodes a flashcard's captured `source_line` in the pipe notation
/// shared with the web (`lib/lyrics/parse-ruby.ts` `PIPE_RE`): each annotation
/// token is `｜base｜reading｜` (fullwidth pipe U+FF5C), with an empty reading for
/// kana / non-kanji words. Bare text between tokens is left unannotated. The
/// column is plain `text`, so both clients must read each other's rows — iOS
/// encodes a captured line into this form and decodes a stored line (web- or
/// iOS-written) back into ruby cells, without re-running the tokenizer.
nonisolated enum SourceLineCodec {
  /// The fullwidth pipe (U+FF5C) that delimits an annotation token.
  private static let pipe: Character = "｜"

  /// Serialize an annotated line's cells into pipe notation for storage. Cells are
  /// grouped back into their words (consecutive cells share a `wordSurface`), and
  /// each word is emitted as `｜surface｜reading｜` — the reading present only for a
  /// kanji-bearing word whose reading differs from its surface, empty otherwise —
  /// so `stripAnnotations` recovers the original line and the web's `parseRuby`
  /// renders it identically.
  static func encode(_ tokens: [RubyToken]) -> String {
    var out = ""
    var index = tokens.startIndex
    while index < tokens.endIndex {
      let surface = tokens[index].wordSurface
      let reading = tokens[index].wordReading
      // Absorb every following cell that belongs to the same word.
      var next = tokens.index(after: index)
      while next < tokens.endIndex,
            tokens[next].wordSurface == surface
      {
        next = tokens.index(after: next)
      }
      let emitReading = FuriganaAnnotator.containsKanji(surface) && reading != surface ? reading : ""
      out += "\(pipe)\(surface)\(pipe)\(emitReading)\(pipe)"
      index = next
    }
    return out
  }

  /// Parse a stored `source_line` into ruby cells for `RubyText`. Each annotation
  /// token becomes okurigana-aligned cells (kanji word with a reading) or a single
  /// plain cell (kana word, empty reading); bare runs between tokens become plain
  /// cells. Every cell carries its word's surface so the study back-face can
  /// highlight the saved word by `wordSurface`. Never tokenizes.
  static func decode(_ line: String) -> [RubyToken] {
    var tokens: [RubyToken] = []
    let scalars = Array(line)
    var i = 0
    var plain = ""

    func flushPlain() {
      guard !plain.isEmpty else { return }
      tokens.append(RubyToken(surface: plain, reading: nil, wordSurface: plain, wordReading: plain))
      plain = ""
    }

    while i < scalars.count {
      guard scalars[i] == pipe else {
        plain.append(scalars[i])
        i += 1
        continue
      }
      // A well-formed token is ｜base｜reading｜. Find the two closing pipes; if the
      // run is malformed, treat the stray pipe as plain text and move on.
      guard let mid = nextPipe(in: scalars, from: i + 1),
            let end = nextPipe(in: scalars, from: mid + 1)
      else {
        plain.append(scalars[i])
        i += 1
        continue
      }
      flushPlain()
      let base = String(scalars[(i + 1) ..< mid])
      let reading = String(scalars[(mid + 1) ..< end])
      if reading.isEmpty {
        tokens.append(RubyToken(surface: base, reading: nil, wordSurface: base, wordReading: base))
      } else {
        tokens.append(contentsOf: FuriganaAnnotator.align(surface: base, reading: reading))
      }
      i = end + 1
    }
    flushPlain()
    return tokens
  }

  /// Drop the annotations, recovering the bare line text — mirrors the web's
  /// `stripAnnotations`.
  static func plainText(_ line: String) -> String {
    decode(line).map(\.surface).joined()
  }

  private static func nextPipe(in scalars: [Character], from start: Int) -> Int? {
    var i = start
    while i < scalars.count {
      if scalars[i] == pipe { return i }
      i += 1
    }
    return nil
  }
}
