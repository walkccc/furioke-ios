import Foundation

/// Converts a flashcard's `source_line` between the pipe-annotation string stored
/// in Supabase (`｜base｜reading｜`, the same notation the web writes and
/// `FuriganaAnnotator` / `rewriteAnnotationReading` produce) and the `[RubyToken]`
/// stream the lyric surface's ruby layout renders. Because the reading is baked
/// into the stored string, parsing needs no tokenizer — it is synchronous and
/// offline, unlike the live lyric path that runs kuromoji.
nonisolated enum SourceLineCodec {
  private static let pipe = "｜"

  /// Serialize a captured annotated line's tokens into pipe notation. The tokens
  /// are already split at okurigana, but each carries its whole word via
  /// `wordSurface`/`wordReading`; consecutive cells are regrouped into one
  /// `｜word｜reading｜` per kanji word (reading differs from surface) and bare
  /// text for plain runs. A word's cells are contiguous and their `surface`s
  /// concatenate to `wordSurface`, which bounds each group — correct even when
  /// the same word repeats on the line.
  static func serialize(_ tokens: [RubyToken]) -> String {
    var out = ""
    var i = 0
    while i < tokens.count {
      let word = tokens[i].wordSurface
      let reading = tokens[i].wordReading
      // Consume the contiguous run of cells whose surfaces rebuild this word.
      var combined = ""
      var j = i
      while j < tokens.count,
            tokens[j].wordSurface == word,
            tokens[j].wordReading == reading
      {
        combined += tokens[j].surface
        j += 1
        if combined == word { break }
      }
      if reading != word, !reading.isEmpty {
        out += pipe + word + pipe + reading + pipe
      } else if tokens[i].saveable {
        // A kana content word — no furigana, but kept as a clickable/saveable
        // unit via the empty-reading form ｜word｜｜ (shared with the web), so the
        // study card can mark it inside its source line.
        out += pipe + word + pipe + pipe
      } else {
        out += combined.isEmpty ? word : combined
      }
      i = max(j, i + 1)
    }
    return out
  }

  /// Parse a stored pipe-annotation line into ruby tokens: bare text between
  /// matches becomes a plain token, and each `｜base｜reading｜` runs through the
  /// shared okurigana alignment (`FuriganaAnnotator.align`, the same split the
  /// live lyric annotator uses), so the card splits kanji runs identically.
  static func parse(_ line: String) -> [RubyToken] {
    guard !line.isEmpty else { return [] }
    // The reading may be empty (｜base｜｜): a saveable kana word with no furigana.
    let regex = /｜([^｜]+)｜([^｜]*)｜/
    var tokens: [RubyToken] = []
    var cursor = line.startIndex
    for match in line.matches(of: regex) {
      if match.range.lowerBound > cursor {
        appendPlain(String(line[cursor ..< match.range.lowerBound]), to: &tokens)
      }
      let base = String(match.output.1)
      let reading = String(match.output.2)
      if reading.isEmpty {
        // A kana word: one plain cell, no furigana, but a whole-word unit so the
        // study card can highlight it against the saved `surface`.
        tokens.append(RubyToken(
          surface: base,
          reading: nil,
          wordSurface: base,
          wordReading: base,
          saveable: true
        ))
      } else {
        tokens.append(contentsOf: FuriganaAnnotator.align(
          surface: base,
          reading: reading,
          saveable: true
        ))
      }
      cursor = match.range.upperBound
    }
    if cursor < line.endIndex {
      appendPlain(String(line[cursor...]), to: &tokens)
    }
    return tokens
  }

  /// Drop every `｜base｜reading｜` annotation down to its base text, for feeding a
  /// source line to the translation route (mirrors the web's `stripAnnotations`).
  static func stripAnnotations(_ line: String) -> String {
    guard !line.isEmpty else { return line }
    let regex = /｜([^｜]+)｜([^｜]*)｜/
    var out = ""
    var cursor = line.startIndex
    for match in line.matches(of: regex) {
      out += line[cursor ..< match.range.lowerBound]
      out += match.output.1
      cursor = match.range.upperBound
    }
    out += line[cursor...]
    return out
  }

  private static func appendPlain(_ text: String, to tokens: inout [RubyToken]) {
    guard !text.isEmpty else { return }
    tokens.append(RubyToken(surface: text, reading: nil, wordSurface: text, wordReading: text))
  }
}
