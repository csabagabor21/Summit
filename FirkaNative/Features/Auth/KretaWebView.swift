import SwiftUI
import WebKit

struct KretaWebView: UIViewRepresentable {
    var onCode: (String) -> Void
    var onDemo: (() -> Void)?
    /// Hiba-visszajelzés a hívónak. A demo-ba lépés SOHA nem automatikus:
    /// csak a user kifejezett koppintására történik (App Store 2.2).
    var onError: ((String) -> Void)?

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

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode, onDemo: onDemo, onError: onError) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onCode: (String) -> Void
        let onDemo: (() -> Void)?
        let onError: ((String) -> Void)?
        var didHandle = false
        init(onCode: @escaping (String)->Void, onDemo: (() -> Void)?, onError: ((String) -> Void)? = nil) { self.onCode = onCode; self.onDemo = onDemo; self.onError = onError }

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
            // Nincs auto-demo: csak jelezzük a hibát, a user dönt.
            if let onError { DispatchQueue.main.async { onError(error.localizedDescription) } }
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let ns = error as NSError
            if ns.code == NSURLErrorCancelled || ns.code == 102 { return }
            if !didHandle, let onError { DispatchQueue.main.async { onError(error.localizedDescription) } }
        }
    }
}
