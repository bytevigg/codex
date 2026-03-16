import Foundation
import WebKit
import Combine

/// Manages a WKWebView that loads YouTube and provides pause/play/metadata via injected JS.
@MainActor
final class YouTubePlayerBridge: NSObject, ObservableObject {
    @Published var isPlaying = false
    @Published var currentMetadata: VideoMetadata?

    private(set) var webView: WKWebView!

    private var metadataContinuation: CheckedContinuation<VideoMetadata?, Never>?

    override init() {
        super.init()

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let controller = config.userContentController

        // Inject a helper script that exposes control functions
        let helperJS = """
        window.__ytBuddy = {
            pause: function() {
                var v = document.querySelector('video');
                if (v) { v.pause(); return 'ok'; }
                return 'no-video';
            },
            play: function() {
                var v = document.querySelector('video');
                if (v) { v.play(); return 'ok'; }
                return 'no-video';
            },
            metadata: function() {
                var url = location.href;
                var title = document.title || '';
                var channel = '';
                var el = document.querySelector('#channel-name a')
                      || document.querySelector('ytd-channel-name a')
                      || document.querySelector('.slim-owner-channel-name');
                if (el) channel = el.textContent.trim();
                var desc = '';
                var meta = document.querySelector('meta[name="description"]');
                if (meta) desc = meta.content || '';
                var vidId = '';
                try {
                    var params = new URLSearchParams(new URL(url).search);
                    vidId = params.get('v') || '';
                } catch(e) {}
                return JSON.stringify({
                    videoId: vidId, title: title,
                    channelName: channel, description: desc
                });
            }
        };
        """
        let script = WKUserScript(source: helperJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        controller.addUserScript(script)

        // Listen for playing/paused state changes
        let stateObserver = """
        (function() {
            var lastState = '';
            setInterval(function() {
                var v = document.querySelector('video');
                if (!v) return;
                var state = v.paused ? 'paused' : 'playing';
                if (state !== lastState) {
                    lastState = state;
                    window.webkit.messageHandlers.playbackState.postMessage(state);
                }
            }, 500);
        })();
        """
        let stateScript = WKUserScript(source: stateObserver, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        controller.addUserScript(stateScript)
        controller.add(self, name: "playbackState")
        controller.add(self, name: "metadataResult")

        webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true

        // Use mobile Safari user agent to avoid "get the app" banners
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

        loadYouTube()
    }

    func loadYouTube() {
        guard let url = URL(string: "https://m.youtube.com") else { return }
        webView.load(URLRequest(url: url))
    }

    func loadVideo(id: String) {
        guard let url = URL(string: "https://m.youtube.com/watch?v=\(id)") else { return }
        webView.load(URLRequest(url: url))
    }

    // MARK: - Playback control

    func pause() async -> Bool {
        await runJS("window.__ytBuddy ? window.__ytBuddy.pause() : 'no-helper'") == "ok"
    }

    func resume() async -> Bool {
        await runJS("window.__ytBuddy ? window.__ytBuddy.play() : 'no-helper'") == "ok"
    }

    // MARK: - Metadata

    func fetchMetadata() async -> VideoMetadata? {
        guard let json = await runJS("window.__ytBuddy ? window.__ytBuddy.metadata() : ''"),
              !json.isEmpty,
              let data = json.data(using: .utf8) else {
            return nil
        }
        struct Raw: Decodable {
            let videoId: String
            let title: String
            let channelName: String
            let description: String
        }
        guard let raw = try? JSONDecoder().decode(Raw.self, from: data) else { return nil }
        let meta = VideoMetadata(
            videoId: raw.videoId, title: raw.title,
            channelName: raw.channelName, description: raw.description
        )
        currentMetadata = meta
        return meta
    }

    // MARK: - JS execution

    private func runJS(_ js: String) async -> String? {
        try? await webView.evaluateJavaScript(js) as? String
    }
}

// MARK: - WKScriptMessageHandler

extension YouTubePlayerBridge: WKScriptMessageHandler {
    nonisolated func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        Task { @MainActor in
            if message.name == "playbackState", let state = message.body as? String {
                isPlaying = (state == "playing")
            }
        }
    }
}
