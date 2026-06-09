import Foundation
import Observation
import UIKit
import WebKit

/// The five playback states the YouTube IFrame Player reports via `onStateChange`.
/// Raw values match `YT.PlayerState`.
nonisolated enum YouTubePlayerState: Int {
  case unstarted = -1
  case ended = 0
  case playing = 1
  case paused = 2
  case buffering = 3
  case cued = 5
}

/// Owns the `WKWebView` hosting the YouTube IFrame Player and the JS bridge in/out
/// of it. This is the single seam that lets YouTube play in-app while keeping
/// `MusicState` headless: the controller is constructed once at the composition
/// root, injected into `YouTubeAdapter` (which drives it and reads its callbacks)
/// and into `YouTubePlayerView` (which displays its `webView`).
///
/// Position is *pulled* — the adapter starts/stops a `getCurrentTime()` poll while
/// playing, and each tick feeds `MusicUpdate.positionMs` through the existing
/// `MusicState` anchor/interpolation. JS events (`onReady` / `onStateChange` /
/// `onError`) are bridged back through a single `WKScriptMessageHandler`.
@Observable
@MainActor
final class YouTubePlayerController: NSObject {
  /// The web view displayed by `YouTubePlayerView`. Not observed (its identity
  /// never changes; only its content does, driven via JS).
  @ObservationIgnored let webView: WKWebView

  // Callbacks the adapter wires up. Defaults are no-ops so the controller is safe
  // to use before an adapter attaches.
  @ObservationIgnored var onReady: () -> Void = {}
  @ObservationIgnored var onStateChange: (YouTubePlayerState) -> Void = { _ in }
  @ObservationIgnored var onError: (Int) -> Void = { _ in }
  /// `(currentTimeSeconds, durationSeconds)` from each poll tick.
  @ObservationIgnored var onTimeUpdate: (Double, Double) -> Void = { _, _ in }

  @ObservationIgnored private var isReady = false
  /// A `load` requested before the IFrame API finished booting; flushed on ready.
  @ObservationIgnored private var pendingLoad: String?
  @ObservationIgnored private var pollTask: Task<Void, Never>?

  override init() {
    let config = WKWebViewConfiguration()
    // Inline + no user-action gate: the play originates from the user's tap on a
    // track row, which is the gesture WebKit requires, and the video must stay
    // embedded rather than going fullscreen.
    config.allowsInlineMediaPlayback = true
    config.mediaTypesRequiringUserActionForPlayback = []
    config.userContentController = WKUserContentController()
    webView = WKWebView(frame: .zero, configuration: config)

    super.init()

    webView.isOpaque = false
    webView.backgroundColor = .black
    webView.scrollView.isScrollEnabled = false
    // The controller is an app-lifetime singleton, so the handler retain cycle
    // (contentController → self) is intentional and harmless.
    config.userContentController.add(self, name: "yt")
    // Load the IFrame host page from the real furioke.com origin (not
    // `loadHTMLString`). WKWebView gives locally-loaded HTML no real HTTP origin
    // / Referer, which YouTube's embed validation now rejects as "Video
    // unavailable" (error 150/152/153) even for freely-embeddable videos.
    // Serving the player from an https origin gives the embed a valid Referer;
    // the JS bridge below works identically against the remote page.
    let playerURL = BackendConfig.apiBaseURL.appendingPathComponent("embed/youtube")
    webView.load(URLRequest(url: playerURL))
  }

  // MARK: Commands (Swift → JS)

  /// Load and start a video id. Before the IFrame API is ready the request is
  /// buffered and flushed on `onReady`.
  func load(videoId: String) {
    guard isReady else { pendingLoad = videoId
      return
    }
    eval("loadVideo('\(escape(videoId))')")
  }

  func play() {
    eval("playVideo()")
  }

  func pause() {
    eval("pauseVideo()")
  }

  func seek(seconds: Double) {
    eval("seekTo(\(seconds))")
  }

  /// Set the IFrame player's playback rate. Calls `window.player.setPlaybackRate`
  /// directly (like `stop()`), so the remote embed host page needs no helper.
  func setPlaybackRate(_ rate: Double) {
    eval(
      "if (window.player && window.player.setPlaybackRate) { window.player.setPlaybackRate(\(rate)); }"
    )
  }

  /// Stop playback and the poll. Called on provider switch / disconnect so no
  /// hidden web player keeps running once YouTube is no longer the active source.
  func stop() {
    stopPolling()
    pendingLoad = nil
    eval("if (window.player && window.player.stopVideo) { window.player.stopVideo(); }")
  }

  // MARK: Position polling

  /// Poll `getCurrentTime()` / `getDuration()` ~every 400 ms. The adapter starts
  /// this on `.playing` and stops it on pause / buffer / end, so position only
  /// advances while real content is playing (an ad's timeline never re-anchors).
  func startPolling() {
    pollTask?.cancel()
    pollTask = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        await pollTime()
        try? await Task.sleep(for: .milliseconds(400))
      }
    }
  }

  func stopPolling() {
    pollTask?.cancel()
    pollTask = nil
  }

  private func pollTime() async {
    let js = """
    JSON.stringify([
      (window.player && window.player.getCurrentTime) ? window.player.getCurrentTime() : 0,
      (window.player && window.player.getDuration) ? window.player.getDuration() : 0
    ])
    """
    guard
      let raw = try? await webView.evaluateJavaScript(js),
      let string = raw as? String,
      let data = string.data(using: .utf8),
      let pair = try? JSONSerialization.jsonObject(with: data) as? [Double],
      pair.count == 2
    else { return }
    onTimeUpdate(pair[0], pair[1])
  }

  // MARK: JS bridge plumbing

  private func eval(_ js: String) {
    webView.evaluateJavaScript(js, completionHandler: nil)
  }

  /// Single-quote escape for the only interpolated value (a video id); ids are
  /// `[A-Za-z0-9_-]` in practice, this is belt-and-suspenders.
  private func escape(_ value: String) -> String {
    value.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "'", with: "\\'")
  }

  private func handle(event: String, data: Any?) {
    switch event {
    case "ready":
      isReady = true
      if let pending = pendingLoad {
        pendingLoad = nil
        eval("loadVideo('\(escape(pending))')")
      }
      onReady()
    case "state":
      if let code = data as? Int, let state = YouTubePlayerState(rawValue: code) {
        onStateChange(state)
      }
    case "error":
      if let code = data as? Int { onError(code) }
    default:
      break
    }
  }
}

/// WebKit delivers script messages on the main thread, so assuming main-actor
/// isolation here is safe; the conformance is `nonisolated` only to satisfy the
/// `WKScriptMessageHandler` ObjC protocol on this `@MainActor` class.
extension YouTubePlayerController: WKScriptMessageHandler {
  nonisolated func userContentController(
    _: WKUserContentController,
    didReceive message: WKScriptMessage
  ) {
    guard
      let body = message.body as? [String: Any],
      let event = body["event"] as? String
    else { return }
    let data = body["data"]
    MainActor.assumeIsolated {
      self.handle(event: event, data: data)
    }
  }
}
