import SwiftUI
import WebKit

struct KretaWebView: UIViewRepresentable {
    var onCode: (String) -> Void
    var onDemo: (() -> Void)?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        wv.navigationDelegate = context.coordinator
        wv.load(URLRequest(url: KretaAPI.authorizeURL))
        return wv
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode, onDemo: onDemo) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onCode: (String) -> Void
        let onDemo: (() -> Void)?
        var didHandle = false
        init(onCode: @escaping (String)->Void, onDemo: (() -> Void)?) { self.onCode = onCode; self.onDemo = onDemo }

        func webView(_ webView: WKWebView, decidePolicyFor nav: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy)->Void) {
            if let url = nav.request.url, url.absoluteString.hasPrefix(KretaAPI.redirectURI),
               let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let code = comps.queryItems?.first(where: { $0.name == "code" })?.value, !code.isEmpty, !didHandle {
                didHandle = true
                onCode(code)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            // Auto-fallback to demo if outside HU (Flutter does same)
            if let onDemo { DispatchQueue.main.async { onDemo() } }
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let ns = error as NSError
            if ns.code == NSURLErrorCancelled || ns.code == 102 { return }
            if let onDemo, !didHandle { DispatchQueue.main.async { onDemo() } }
        }
    }
}
