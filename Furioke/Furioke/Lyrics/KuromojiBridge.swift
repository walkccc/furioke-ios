import Foundation
import JavaScriptCore

/// Runs the bundled kuromoji.js tokenizer inside JavaScriptCore so iOS produces
/// byte-identical tokenizer output to the web app (same JS, same dictionary).
///
/// The bundled kuromoji build loads its dictionary through `XMLHttpRequest` and
/// gunzips each `.dat.gz` with its own bundled zlib. JavaScriptCore has no XHR,
/// so we install a tiny shim that resolves each request to the gzipped bytes of
/// the matching bundle resource — the JS-side zlib still does the decompression,
/// so no Swift gunzip is needed and no network access ever occurs.
///
/// The actor confines the (non-Sendable) `JSContext` to a single isolation
/// domain and keeps it cached for the whole session so the ~500ms dict parse is
/// paid once. `purge()` drops the context for memory-warning handling.
actor KuromojiBridge {
  static let shared = KuromojiBridge()

  nonisolated struct Token: Equatable {
    let surface: String
    /// kuromoji's per-token reading in katakana, or nil when it has none.
    let reading: String?
  }

  nonisolated enum Error: Swift.Error {
    case contextCreationFailed
    case resourceMissing(String)
    case arrayBufferCreationFailed(String)
    case javaScript(String)
    case tokenizerBuildFailed(String)
    case tokenizerUnavailable
  }

  private var context: JSContext?

  /// The kuromoji IPADIC dictionary, in the load order the JS loader requests.
  private static let dictFilenames = [
    "base.dat.gz", "check.dat.gz",
    "tid.dat.gz", "tid_pos.dat.gz", "tid_map.dat.gz",
    "cc.dat.gz",
    "unk.dat.gz", "unk_pos.dat.gz", "unk_map.dat.gz",
    "unk_char.dat.gz", "unk_compat.dat.gz", "unk_invoke.dat.gz",
  ]

  /// Builds and caches the tokenizer without tokenizing anything. Callers can
  /// run this off the critical path (e.g. on entering Now Playing) so the first
  /// real lyric line does not wait on the dict parse.
  func preload() throws {
    try ensureReady()
  }

  func tokenize(_ text: String) throws -> [Token] {
    try ensureReady()
    guard let context, let tokenizeFn = context.objectForKeyedSubscript("__tokenize") else {
      throw Error.tokenizerUnavailable
    }
    let result = tokenizeFn.call(withArguments: [text])
    try checkException(context, stage: "tokenize")
    let json = result?.toString() ?? "[]"
    let raw = try JSONDecoder().decode([RawToken].self, from: Data(json.utf8))
    return raw.map { Token(surface: $0.s, reading: $0.r) }
  }

  /// Releases the JSContext (~30–50MB with the parsed dict). The next tokenize
  /// call re-instantiates and pays the first-call cost again.
  func purge() {
    context = nil
  }

  private func ensureReady() throws {
    if context != nil { return }
    try bootstrap()
  }

  private func bootstrap() throws {
    guard let context = JSContext() else { throw Error.contextCreationFailed }

    // Timer + XHR shims MUST exist before kuromoji.js is evaluated: the
    // bundled `process` shim caches `setTimeout` at require time and drains its
    // nextTick queue through it. Our synchronous timers make the whole dict
    // load (async.parallel under the hood) complete within the build() call.
    context.evaluateScript(Self.runtimeShimJS)
    try checkException(context, stage: "runtime shim")

    try installDictData(into: context)

    guard let url = Self.kuromojiSourceURL(),
          let source = try? String(contentsOf: url, encoding: .utf8)
    else {
      throw Error.resourceMissing("kuromoji.js")
    }
    context.evaluateScript(source, withSourceURL: url)
    try checkException(context, stage: "kuromoji.js")

    context.evaluateScript(Self.tokenizeFnJS)
    try checkException(context, stage: "tokenize function")

    context.evaluateScript(Self.buildJS)
    try checkException(context, stage: "build")

    if context.objectForKeyedSubscript("__kuromojiReady")?.toBool() != true {
      let message = context.objectForKeyedSubscript("__kuromojiError")?.toString()
      throw Error.tokenizerBuildFailed(message ?? "unknown")
    }

    self.context = context
  }

  /// Exposes each gzipped dict file to JS as an ArrayBuffer under
  /// `__dictData[filename]`; the XHR shim looks them up by basename.
  private func installDictData(into context: JSContext) throws {
    guard let dictObject = JSValue(newObjectIn: context) else {
      throw Error.contextCreationFailed
    }
    for filename in Self.dictFilenames {
      guard let url = Self.dictFileURL(filename) else {
        throw Error.resourceMissing(filename)
      }
      guard let data = try? Data(contentsOf: url) else {
        throw Error.resourceMissing(filename)
      }
      guard let buffer = Self.makeArrayBuffer(data, in: context) else {
        throw Error.arrayBufferCreationFailed(filename)
      }
      dictObject.setObject(buffer, forKeyedSubscript: filename as NSString)
    }
    context.setObject(dictObject, forKeyedSubscript: "__dictData" as NSString)
  }

  private func checkException(_ context: JSContext, stage: String) throws {
    if let exception = context.exception {
      context.exception = nil
      throw Error.javaScript("\(stage): \(exception.toString() ?? "unknown error")")
    }
  }

  // MARK: - Resource lookup

  private static func kuromojiSourceURL() -> URL? {
    Bundle.main.url(forResource: "kuromoji", withExtension: "js")
      ?? Bundle.main.url(forResource: "kuromoji", withExtension: "js", subdirectory: "Kuromoji")
  }

  private static func dictFileURL(_ filename: String) -> URL? {
    let name = filename as NSString
    let base = name.deletingPathExtension // e.g. "base.dat"
    let ext = name.pathExtension // "gz"
    return Bundle.main.url(forResource: base, withExtension: ext)
      ?? Bundle.main.url(forResource: base, withExtension: ext, subdirectory: "KuromojiDict")
  }

  /// Wraps `data` in a JS ArrayBuffer without copying through a JSValue bridge.
  /// JavaScriptCore takes ownership of the malloc'd copy and frees it via the
  /// deallocator when the ArrayBuffer is collected.
  private static func makeArrayBuffer(_ data: Data, in context: JSContext) -> JSValue? {
    let length = data.count
    guard length > 0, let copy = malloc(length) else { return nil }
    data.copyBytes(to: UnsafeMutableRawBufferPointer(start: copy, count: length))

    let deallocator: JSTypedArrayBytesDeallocator = { pointer, _ in free(pointer) }
    var exception: JSValueRef?
    let ref = JSObjectMakeArrayBufferWithBytesNoCopy(
      context.jsGlobalContextRef, copy, length, deallocator, nil, &exception
    )
    if exception != nil || ref == nil {
      free(copy)
      return nil
    }
    return JSValue(jsValueRef: ref, in: context)
  }

  private nonisolated struct RawToken: Decodable {
    let s: String
    let r: String?
  }

  // MARK: - Injected JavaScript

  private static let runtimeShimJS = """
  (function (g) {
    g.setTimeout = function (fn) {
      var extra = Array.prototype.slice.call(arguments, 2);
      fn.apply(null, extra);
      return 0;
    };
    g.setInterval = function () { return 0; };
    g.clearTimeout = function () {};
    g.clearInterval = function () {};
    g.setImmediate = function (fn) {
      var extra = Array.prototype.slice.call(arguments, 1);
      fn.apply(null, extra);
      return 0;
    };
    g.clearImmediate = function () {};
    if (typeof g.console === 'undefined') {
      g.console = {
        log: function () {}, warn: function () {},
        error: function () {}, info: function () {},
      };
    }

    function XHR() {}
    XHR.prototype.open = function (method, url) { this._url = url; };
    XHR.prototype.send = function () {
      var name = String(this._url).split('/').pop();
      var buffer = g.__dictData ? g.__dictData[name] : null;
      if (!buffer) {
        this.status = 404;
        if (this.onerror) { this.onerror(new Error('kuromoji dict missing: ' + name)); }
        return;
      }
      this.status = 200;
      this.response = buffer;
      if (this.onload) { this.onload(); }
    };
    g.XMLHttpRequest = XHR;
  })(this);
  """

  private static let tokenizeFnJS = """
  function __tokenize(line) {
    if (!__kuromojiTokenizer) { return '[]'; }
    var tokens = __kuromojiTokenizer.tokenize(line);
    var out = [];
    for (var i = 0; i < tokens.length; i++) {
      out.push({ s: tokens[i].surface_form, r: tokens[i].reading });
    }
    return JSON.stringify(out);
  }
  """

  private static let buildJS = """
  var __kuromojiReady = false;
  var __kuromojiError = null;
  var __kuromojiTokenizer = null;
  (function () {
    try {
      kuromoji.builder({ dicPath: 'dict' }).build(function (err, tokenizer) {
        if (err) {
          __kuromojiError = String(err && err.message ? err.message : err);
          return;
        }
        __kuromojiTokenizer = tokenizer;
        __kuromojiReady = true;
      });
    } catch (e) {
      __kuromojiError = String(e && e.message ? e.message : e);
    }
  })();
  __dictData = null;
  """
}
