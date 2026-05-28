import CryptoKit
import Foundation

/// Per-line fingerprint that binds LRCLIB-timed lines to displayed lyric lines.
/// This is a pure-Swift port of the web's `lib/lyrics/line-hash.ts` and MUST
/// stay byte-identical to it: the hash is the contract between the anchor writer
/// (web) and the iOS runtime renderer, so identical inputs must produce
/// identical hashes on both clients. The 128-bit (32 hex char) truncation
/// matches the web's deliberate column-size tradeoff.
nonisolated enum LineHash {
  private static let hashLenHex = 32

  /// The exact set JS `\s` matches, so whitespace stripping folds identically to
  /// the web regex `/\s+/g`. Foundation's `.whitespacesAndNewlines` is NOT a
  /// match (it adds U+0085 NEL and omits U+FEFF), so the set is spelled out.
  private static let jsWhitespace: Set<Unicode.Scalar> = {
    var set: Set<Unicode.Scalar> = [
      "\u{0009}", "\u{000A}", "\u{000B}", "\u{000C}", "\u{000D}", "\u{0020}",
      "\u{00A0}", "\u{1680}", "\u{2028}", "\u{2029}", "\u{202F}", "\u{205F}",
      "\u{3000}", "\u{FEFF}",
    ]
    for cp in 0x2000 ... 0x200A {
      set.insert(Unicode.Scalar(cp)!)
    }
    return set
  }()

  /// NFKC → strip all whitespace → strip leading/trailing punctuation & symbols.
  /// Case is preserved (no lowercasing), matching the web exactly.
  static func normalize(_ text: String) -> String {
    let folded = text.precomposedStringWithCompatibilityMapping // NFKC
    let withoutWhitespace = folded.unicodeScalars.filter { !jsWhitespace.contains($0) }
    return stripEdgePunctuation(String(String.UnicodeScalarView(withoutWhitespace)))
  }

  /// sha256 of the normalized UTF-8 bytes, hex-encoded, truncated to 128 bits.
  static func hash(_ text: String) -> String {
    let digest = SHA256.hash(data: Data(normalize(text).utf8))
    let hex = digest.map { String(format: "%02x", $0) }.joined()
    return String(hex.prefix(hashLenHex))
  }

  /// Mirrors JS `/^[\p{P}\p{S}]+|[\p{P}\p{S}]+$/gu`: drop the maximal leading and
  /// trailing runs of Unicode punctuation (Pc Pd Ps Pe Pi Pf Po) or symbol
  /// (Sm Sc Sk So) scalars, preserving everything in between.
  private static func stripEdgePunctuation(_ text: String) -> String {
    let scalars = Array(text.unicodeScalars)
    var start = 0
    var end = scalars.count
    while start < end, isPunctuationOrSymbol(scalars[start]) {
      start += 1
    }
    while end > start, isPunctuationOrSymbol(scalars[end - 1]) {
      end -= 1
    }
    return String(String.UnicodeScalarView(scalars[start ..< end]))
  }

  private static func isPunctuationOrSymbol(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.properties.generalCategory {
    case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
         .initialPunctuation, .finalPunctuation, .otherPunctuation,
         .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol:
      true
    default:
      false
    }
  }
}
