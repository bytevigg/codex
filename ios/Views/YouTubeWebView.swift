import SwiftUI
import WebKit

/// Wraps a WKWebView for use in SwiftUI. The bridge owns the WKWebView instance.
struct YouTubeWebView: UIViewRepresentable {
    let bridge: YouTubePlayerBridge

    func makeUIView(context: Context) -> WKWebView {
        bridge.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // No-op: bridge manages the web view state
    }
}
