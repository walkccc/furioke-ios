import Foundation

/// Hepburn romanization of a kana string. Used to render the optional rōmaji row
/// under each lyric line: the furigana pipeline already resolves every kanji run
/// to a hiragana reading, so a line's rōmaji is derived purely on-device from the
/// readings — there is no separate rōmaji payload from the backend.
///
/// Input is expected to be (mostly) hiragana; katakana is folded to hiragana
/// first by the caller's `toHiragana`. Anything that isn't kana — latin,
/// punctuation, digits — passes through unchanged so mixed lines stay readable.
nonisolated enum Romaji {
  static func fromKana(_ input: String) -> String {
    let chars = Array(input)
    var result = ""
    var i = 0
    // A small っ doubles the consonant of the *next* syllable; carry it forward.
    var sokuon = false

    while i < chars.count {
      let c = chars[i]

      if c == "っ" {
        sokuon = true
        i += 1
        continue
      }

      // Prolonged sound mark: lengthen the previous vowel (ラーメン → raamen).
      if c == "ー" {
        if let last = result.last, "aiueo".contains(last) { result.append(last) }
        i += 1
        continue
      }

      // Palatalized digraph (きゃ, しゅ, ちょ, …): base kana + small ya/yu/yo.
      if i + 1 < chars.count,
         Self.smallY.contains(chars[i + 1]),
         let romaji = Self.digraphs[String(c) + String(chars[i + 1])]
      {
        result += Self.applySokuon(&sokuon, romaji)
        i += 2
        continue
      }

      if let romaji = Self.monographs[String(c)] {
        result += Self.applySokuon(&sokuon, romaji)
        i += 1
        continue
      }

      // Non-kana: a dangling sokuon has nothing to double, so drop it.
      sokuon = false
      result.append(c)
      i += 1
    }
    return result
  }

  /// Prefix the geminating consonant when a pending っ is consumed. Hepburn
  /// doubles the first consonant, except before `ch`, which becomes `tch`.
  private static func applySokuon(_ sokuon: inout Bool, _ romaji: String) -> String {
    guard sokuon, let first = romaji.first else { return romaji }
    sokuon = false
    if romaji.hasPrefix("ch") { return "t" + romaji }
    return String(first) + romaji
  }

  private static let smallY: Set<Character> = ["ゃ", "ゅ", "ょ"]

  private static let digraphs: [String: String] = [
    "きゃ": "kya", "きゅ": "kyu", "きょ": "kyo",
    "ぎゃ": "gya", "ぎゅ": "gyu", "ぎょ": "gyo",
    "しゃ": "sha", "しゅ": "shu", "しょ": "sho",
    "じゃ": "ja", "じゅ": "ju", "じょ": "jo",
    "ちゃ": "cha", "ちゅ": "chu", "ちょ": "cho",
    "ぢゃ": "ja", "ぢゅ": "ju", "ぢょ": "jo",
    "にゃ": "nya", "にゅ": "nyu", "にょ": "nyo",
    "ひゃ": "hya", "ひゅ": "hyu", "ひょ": "hyo",
    "びゃ": "bya", "びゅ": "byu", "びょ": "byo",
    "ぴゃ": "pya", "ぴゅ": "pyu", "ぴょ": "pyo",
    "みゃ": "mya", "みゅ": "myu", "みょ": "myo",
    "りゃ": "rya", "りゅ": "ryu", "りょ": "ryo",
  ]

  private static let monographs: [String: String] = [
    "あ": "a", "い": "i", "う": "u", "え": "e", "お": "o",
    "ぁ": "a", "ぃ": "i", "ぅ": "u", "ぇ": "e", "ぉ": "o",
    "か": "ka", "き": "ki", "く": "ku", "け": "ke", "こ": "ko",
    "が": "ga", "ぎ": "gi", "ぐ": "gu", "げ": "ge", "ご": "go",
    "さ": "sa", "し": "shi", "す": "su", "せ": "se", "そ": "so",
    "ざ": "za", "じ": "ji", "ず": "zu", "ぜ": "ze", "ぞ": "zo",
    "た": "ta", "ち": "chi", "つ": "tsu", "て": "te", "と": "to",
    "だ": "da", "ぢ": "ji", "づ": "zu", "で": "de", "ど": "do",
    "な": "na", "に": "ni", "ぬ": "nu", "ね": "ne", "の": "no",
    "は": "ha", "ひ": "hi", "ふ": "fu", "へ": "he", "ほ": "ho",
    "ば": "ba", "び": "bi", "ぶ": "bu", "べ": "be", "ぼ": "bo",
    "ぱ": "pa", "ぴ": "pi", "ぷ": "pu", "ぺ": "pe", "ぽ": "po",
    "ま": "ma", "み": "mi", "む": "mu", "め": "me", "も": "mo",
    "や": "ya", "ゆ": "yu", "よ": "yo",
    "ゃ": "ya", "ゅ": "yu", "ょ": "yo",
    "ら": "ra", "り": "ri", "る": "ru", "れ": "re", "ろ": "ro",
    "わ": "wa", "ゐ": "wi", "ゑ": "we", "を": "o", "ん": "n",
    "ゔ": "vu",
  ]
}
