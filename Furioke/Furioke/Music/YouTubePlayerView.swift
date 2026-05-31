import SwiftUI
import WebKit

/// A thin `UIViewRepresentable` that displays the shared `YouTubePlayerController`'s
/// web view. The controller is the control authority (load / play / pause / seek /
/// poll); this view only mounts its `webView` so the IFrame Player has a visible
/// surface. Mounted by the NowPlaying surface when the active source advertises a
/// `.video` `playerSurface`.
struct YouTubePlayerView: UIViewRepresentable {
  let controller: YouTubePlayerController

  func makeUIView(context _: Context) -> WKWebView {
    controller.webView
  }

  func updateUIView(_: WKWebView, context _: Context) {}
}
