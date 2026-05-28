## ADDED Requirements

### Requirement: Bundled kuromoji.js and dictionary execute inside JavaScriptCore

The iOS app SHALL ship `kuromoji.umd.js` and the kuromoji dictionary files as
bundle resources, and SHALL execute the tokenizer inside Apple's
`JavaScriptCore` framework via a Swift `KuromojiBridge`. The bridge SHALL
override the JS library's default dict-fetch path so dict files load from the
iOS bundle (no network access). The bridge SHALL NOT pull dict files from any
remote URL at any time.

#### Scenario: Tokenizer loads from the bundle

- **WHEN** the app needs to tokenize a lyric line for the first time in a
  session
- **THEN** `JavaScriptCore` evaluates the bundled `kuromoji.umd.js`, resolves
  dict files from the iOS bundle, and produces tokens; no network request is
  issued for tokenizer code or dict files

#### Scenario: No remote dict fetch

- **WHEN** any tokenization call runs
- **THEN** no HTTP request is made for `*.dat`, `*.dat.gz`, or any other
  kuromoji dictionary asset

### Requirement: Tokenizer is module-scope cached for the session

The `KuromojiBridge` SHALL retain its `JSContext` and parsed dictionary at
module scope so the first call's dict-parse cost is paid once per app session.
Subsequent calls SHALL reuse the cached context. On
`applicationDidReceiveMemoryWarning`, the bridge MAY release the `JSContext` and
re-instantiate it on the next call.

#### Scenario: First call pays the dict-load cost

- **WHEN** the first tokenize call of a session runs
- **THEN** the JS context is created, kuromoji.js is evaluated, and the dict is
  loaded (target: under ~700ms on a recent iPhone)

#### Scenario: Subsequent calls are fast

- **WHEN** any tokenize call runs after the first
- **THEN** the cached `JSContext` is reused and tokenization completes in under
  ~5ms per line (no dict reload)

#### Scenario: Memory-warning teardown

- **WHEN** the app receives `applicationDidReceiveMemoryWarning`
- **THEN** the `KuromojiBridge` MAY release its `JSContext` to free ~30–50MB;
  the next tokenize call re-instantiates and pays the first-call cost again

### Requirement: Line-hash algorithm matches the web byte-for-byte

The app SHALL implement the `line_hash` algorithm in pure Swift, matching the
web's `lib/lyrics/line-hash.ts` exactly:

1. Unicode NFKC normalize.
2. Remove all whitespace (replace `/\s+/` with empty string).
3. Strip leading and trailing punctuation characters; preserve internal Japanese
   punctuation (`、`, `。`, `「`, `」`, `（`, `）`, `…`, `―`, etc.).
4. Leave case as-is — no lowercasing.

The hash SHALL be sha256 of the normalized string, hex-encoded, truncated to the
first 32 hex characters (128 bits). Output SHALL be byte-identical to the web
implementation for every possible input.

#### Scenario: Hash byte-equivalence with web

- **WHEN** any lyric line is hashed by both the web's `lib/lyrics/line-hash.ts`
  and the Swift `LineHash` module
- **THEN** the two outputs are byte-identical hex strings

#### Scenario: Internal punctuation participates in the hash

- **WHEN** two lyric lines differ only in an internal Japanese punctuation mark
  (e.g., `、` present vs. absent)
- **THEN** their `line_hash` values differ

#### Scenario: Edge whitespace and punctuation are normalised away

- **WHEN** two lyric lines differ only in trailing whitespace, leading
  punctuation, or interspersed whitespace runs
- **THEN** their `line_hash` values are identical

### Requirement: Built-in seed correction map shared with web

The app SHALL load the same built-in seed correction map the web app uses, from
a shared file at `lib/lyrics/seed.json`, copied into the iOS bundle as a
build-phase artifact. The seed file SHALL be the single source of truth; both
clients SHALL import it without redefining its contents.

#### Scenario: Seed file is shared, not duplicated

- **WHEN** the repository is inspected
- **THEN** `lib/lyrics/seed.json` exists at the repo root and is referenced both
  by the web app's furigana pipeline and by the iOS Xcode "Copy Bundle
  Resources" build phase; no second copy of the seed exists in `ios/`

#### Scenario: Seed correction applies without user setup

- **WHEN** any user — signed in or anonymous — opens a song whose lyrics contain
  a seed-mapped surface (e.g., `二人`)
- **THEN** the seed reading is applied during tokenization without user
  configuration

### Requirement: Correction map combines seed and personal overrides

For each annotation pass, the iOS app SHALL build a `CorrectionMap` combining
the bundled seed (entries from `seed.json`) with the user's personal overrides
from `OverrideEntity` (see [[ios-offline-cache]]). Personal overrides SHALL take
precedence over the seed when a surface appears in both. Phrase matching SHALL
be a greedy longest match over the token sequence: a mapped compound SHALL be
corrected whether kuromoji emits it as one token or splits it.

#### Scenario: Compound is corrected even when kuromoji splits it

- **WHEN** kuromoji tokenizes `二人` as `二` + `人` and the map contains
  `二人 → ふたり`
- **THEN** the phrase-level match still applies and the rendered annotation for
  that compound is `二人` with reading `ふたり`

#### Scenario: Personal override beats the seed

- **WHEN** the user has a personal override for a surface the seed also covers
- **THEN** the personal override's reading is used in the rendered annotation

#### Scenario: Unmapped tokens keep kuromoji's reading

- **WHEN** an annotation pass runs over a kanji token no map entry covers
- **THEN** that token keeps the reading kuromoji produced

### Requirement: Pipeline produces annotated lines in memory only

The `FuriganaPipeline` SHALL accept a raw LRC body and a `CorrectionMap` and
SHALL return an `[AnnotatedLine]` value carrying the surface, reading per kanji
token, and `lineHash` per line. The annotated value SHALL live only in memory
and SHALL NOT be persisted to SwiftData (the raw LRC body is the persisted form
— see [[ios-offline-cache]]).

#### Scenario: Annotation is in-memory only

- **WHEN** the pipeline produces an `[AnnotatedLine]` for a song
- **THEN** the value is held in a SwiftUI view-model property in memory; no
  SwiftData write occurs for tokenized output

#### Scenario: Pipeline is deterministic

- **WHEN** the pipeline is run twice on the same `(bodyText, CorrectionMap)`
  inputs
- **THEN** the two `[AnnotatedLine]` outputs are equal

### Requirement: Pipeline re-runs on override changes

The Now Playing surface SHALL re-run the pipeline against the cached raw LRC
body whenever the user's override map changes (an inline editor confirm, a
settings-dialog edit, or a sync-down from Supabase). The re-run SHALL produce a
new `[AnnotatedLine]` value that the view re-renders against without a
`/api/lyrics` round-trip.

#### Scenario: Inline editor confirm re-renders

- **WHEN** the user confirms an inline reading editor with **Apply to all
  songs** enabled
- **THEN** the `CorrectionMap` is rebuilt with the new override, the pipeline
  re-runs over the cached body, and the rendered lyrics reflect the new reading
  within one render frame, with no `/api/lyrics` call
