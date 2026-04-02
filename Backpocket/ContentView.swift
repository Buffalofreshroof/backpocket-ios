import SwiftUI
import WebKit

struct ContentView: View {
    var body: some View {
        WebView(url: URL(string: "https://backpocket.backpocketbets.de")!)
            .ignoresSafeArea(edges: .bottom)
    }
}

struct WebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        wv.allowsBackForwardNavigationGestures = true
        wv.isOpaque = false
        wv.backgroundColor = UIColor(red: 15/255, green: 17/255, blue: 23/255, alpha: 1)
        wv.scrollView.backgroundColor = wv.backgroundColor
        wv.load(URLRequest(url: url))
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate {
        private var tokenSent = false

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url, let host = url.host, !host.contains("backpocketbets.de") {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !tokenSent else { return }
            guard let token = AppDelegate.deviceToken else { return }

            // Check if user is logged in by reading session email from the page
            let js = """
            (function() {
                var el = document.querySelector('[data-user-email]');
                if (el) return el.getAttribute('data-user-email');
                // Fallback: check if on dashboard (means logged in)
                if (window.location.pathname.includes('dashboard')) {
                    return document.querySelector('.navbar')?.textContent?.match(/[\\w.+-]+@[\\w-]+\\.[\\w.]+/)?.[0] || '';
                }
                return '';
            })()
            """
            webView.evaluateJavaScript(js) { result, _ in
                // Try to get email from page; if on dashboard, use a cookie-based approach
                let email = (result as? String) ?? ""
                if !email.isEmpty {
                    self.registerToken(token: token, email: email)
                } else if webView.url?.path.contains("dashboard") == true {
                    // User is logged in but we can't extract email from JS
                    // Try fetching it from the session API
                    self.fetchEmailAndRegister(webView: webView, token: token)
                }
            }
        }

        private func fetchEmailAndRegister(webView: WKWebView, token: String) {
            // Use a simple fetch inside the webview to get the logged-in user's email
            let js = """
            fetch('/api/get-p2-data.php').then(r => r.json()).then(d => d.email || '').catch(() => '')
            """
            webView.evaluateJavaScript(js) { result, _ in
                if let email = result as? String, !email.isEmpty {
                    self.registerToken(token: token, email: email)
                }
            }
        }

        private func registerToken(token: String, email: String) {
            tokenSent = true
            guard let url = URL(string: "https://backpocket.backpocketbets.de/api/register-device.php") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body = ["email": email, "device_token": token]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let html = "<html><head><meta name='viewport' content='width=device-width,initial-scale=1'><style>body{font-family:-apple-system,sans-serif;background:#0f1117;color:#e2e8f0;display:flex;align-items:center;justify-content:center;min-height:100vh;text-align:center}button{background:#6366f1;color:#fff;border:none;padding:.75rem 2rem;border-radius:.5rem;font-size:1rem}</style></head><body><div><h1>You're Offline</h1><p style='color:#94a3b8'>Check your connection and try again.</p><button onclick='location.reload()'>Retry</button></div></body></html>"
            webView.loadHTMLString(html, baseURL: nil)
        }
    }
}
