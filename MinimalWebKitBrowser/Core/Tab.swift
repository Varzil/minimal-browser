import WebKit
import Foundation
import AppKit

// MARK: - TabContext
//
// The narrow interface a `Tab` needs from its owner (`TabManager`). Keeping it
// a protocol means `Tab` has no hard dependency on `TabManager` and is easy to
// test or reuse.

@MainActor
protocol TabContext: AnyObject {
    var settings: BrowserSettings { get }
    var contentRuleList: WKContentRuleList? { get }
    /// Called for `target=_blank` / JS `window.open`. Returns the new web view
    /// to satisfy `WKUIDelegate.createWebViewWith`.
    func requestNewTab(for request: URLRequest, configuration: WKWebViewConfiguration?) -> WKWebView?
    /// Called when a navigation becomes a download.
    func handleDownload(_ download: WKDownload)
}

// MARK: - Tab
//
// A single browser tab. The key to low memory is that a Tab owns its `WKWebView`
// *lazily*: a background/restored tab starts as just (id, url, title) and only
// spins up a real web view when it is shown or navigated. `unload()` tears the
// web view back down to that featherweight state after inactivity.
//
// `WKWebView` is created and destroyed only here, so this is the one place that
// controls resident memory and per-tab process cost.

@MainActor
final class Tab: ObservableObject, Identifiable {

    let id: UUID

    // Published UI state — drives the tab bar + toolbar. These survive unloading
    // (we keep the last-known title/url so the UI stays stable across unload/reload).
    @Published private(set) var title: String
    @Published private(set) var displayURL: String
    @Published private(set) var estimatedProgress: Double = 0
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var canGoBack: Bool = false
    @Published private(set) var canGoForward: Bool = false
    @Published private(set) var isLoaded: Bool = false   // does a live WKWebView exist?
    @Published private(set) var faviconURL: URL?          // for sidebar display

    /// The URL to (re)load when the web view is materialized.
    private(set) var pendingURL: URL?
    /// The URL the user is currently editing in the address bar (may differ during typing).
    var addressBarText: String = ""

    var lastActiveDate: Date

    /// Pinned tabs show as icon-only at the top of the sidebar (Zen-style "essentials").
    var isPinned: Bool = false

    /// The live web view, or nil if unloaded. Access via `loadIfNeeded()`.
    private(set) var webView: WKWebView?
    private var observers: [NSKeyValueObservation] = []
    /// NSObject shim that owns the WKNavigationDelegate/WKUIDelegate conformance
    /// (those protocols require NSObject). It forwards everything back here.
    private var delegateShim: TabDelegate?

    weak var context: TabContext?

    init(id: UUID = UUID(), url: URL?, title: String = "", context: TabContext?, isPinned: Bool = false) {
        self.id = id
        self.pendingURL = url
        self.title = title.isEmpty ? (url == nil ? "New Tab" : URLUtils.displayString(for: url)) : title
        self.displayURL = URLUtils.displayString(for: url)
        self.lastActiveDate = Date()
        self.isPinned = isPinned
        self.context = context
        self.addressBarText = URLUtils.displayString(for: url)
    }

    // MARK: - Lifecycle

    /// Materialize the WKWebView if needed, then load `pendingURL`.
    /// Idempotent and cheap when already loaded. Called by `WebViewHost` on
    /// selection and by `TabManager` for forced navigations.
    @discardableResult
    func loadIfNeeded() -> WKWebView {
        if let wv = webView { return wv }

        guard let ctx = context else {
            // No context (e.g. during teardown) — still create a minimal view.
            return createWebView()
        }
        return createWebView(using: ctx.settings, ruleList: ctx.contentRuleList)
    }

    private func createWebView(
        using settings: BrowserSettings? = nil,
        ruleList: WKContentRuleList? = nil
    ) -> WKWebView {
        let s = settings ?? context?.settings ?? BrowserSettings()
        let config = WebViewConfig.makeConfiguration(settings: s, contentRuleList: ruleList)
        let wv = WebViewConfig.makeWebView(configuration: config, settings: s)
        let shim = TabDelegate()
        shim.tab = self
        wv.navigationDelegate = shim
        wv.uiDelegate = shim
        delegateShim = shim
        webView = wv
        isLoaded = true
        installObservers(for: wv)
        startInitialLoad(into: wv, settings: s)
        return wv
    }

    private func startInitialLoad(into wv: WKWebView, settings: BrowserSettings) {
        if let url = pendingURL {
            wv.load(URLRequest(url: url))
        } else {
            NewTabPage.load(into: wv, dark: isDarkAppearance)
        }
    }

    /// Tear down the WKWebView, reclaiming its memory + process budget.
    /// Tab identity (id/url/title) is preserved so the tab bar is unchanged.
    func unload() {
        guard let wv = webView else { return }
        // Snapshot live state first so the UI stays consistent.
        if let url = wv.url { pendingURL = url }
        if let t = wv.title, !t.isEmpty { title = t }
        wv.stopLoading()
        wv.navigationDelegate = nil
        wv.uiDelegate = nil
        wv.removeFromSuperview()
        observers.forEach { $0.invalidate() }; observers = []
        webView = nil
        delegateShim = nil
        isLoaded = false
        isLoading = false
        estimatedProgress = 0
        objectWillChange.send()
    }

    // MARK: - Navigation commands

    func load(_ url: URL) {
        pendingURL = url
        addressBarText = URLUtils.displayString(for: url)
        displayURL = addressBarText
        lastActiveDate = Date()
        let wv = loadIfNeeded()
        wv.load(URLRequest(url: url))
    }

    func reload() {
        if let wv = webView { wv.reload() }
        else if let url = pendingURL { load(url) }
        else if let wv = webView { NewTabPage.load(into: wv, dark: isDarkAppearance) }
    }

    func stop() { webView?.stopLoading() }

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }

    /// Re-apply settings that can change live without rebuilding the web view.
    ///
    /// Note: `pageZoom` and `customUserAgent` are genuinely live-settable on an
    /// existing WKWebView. Other knobs (JS toggle, content blockers, inactive
    /// scheduling policy, media policy) are read at web-view creation time, so
    /// they take effect on the *next* tab or after an unload→reload. This is an
    /// intentional trade-off: recreating web views on every setting change would
    /// wreck the snappiness we're optimizing for.
    func applyLiveSettings(_ settings: BrowserSettings) {
        guard let wv = webView else { return }
        wv.pageZoom = CGFloat(settings.pageZoom)
        wv.customUserAgent = settings.customUserAgent  // "" restores WebKit default
    }

    var hostGlyph: String { URLUtils.hostGlyph(for: pendingURL) }

    var isSecure: Bool { (webView?.url?.scheme ?? pendingURL?.scheme) == "https" }

    var isDarkAppearance: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    // MARK: - KVO

    private func installObservers(for wv: WKWebView) {
        observers = [
            wv.observe(\.title, options: [.new, .initial]) { [weak self] wv, _ in
                Task { @MainActor in
                    self?.title = wv.title?.isEmpty == false ? wv.title! : URLUtils.displayString(for: wv.url)
                }
            },
            wv.observe(\.url, options: [.new, .initial]) { [weak self] wv, _ in
                Task { @MainActor in
                    let d = URLUtils.displayString(for: wv.url)
                    self?.displayURL = d
                    if wv.url != nil { self?.pendingURL = wv.url }
                    // Don't clobber the field while the user is actively typing.
                    if !(self?.isLoading ?? false) || self?.addressBarText.isEmpty == true {
                        self?.addressBarText = d
                    }
                }
            },
            wv.observe(\.estimatedProgress, options: [.new, .initial]) { [weak self] wv, _ in
                Task { @MainActor in self?.estimatedProgress = wv.estimatedProgress }
            },
            wv.observe(\.isLoading, options: [.new, .initial]) { [weak self] wv, _ in
                Task { @MainActor in self?.isLoading = wv.isLoading }
            },
            wv.observe(\.canGoBack, options: [.new, .initial]) { [weak self] wv, _ in
                Task { @MainActor in self?.canGoBack = wv.canGoBack }
            },
            wv.observe(\.canGoForward, options: [.new, .initial]) { [weak self] wv, _ in
                Task { @MainActor in self?.canGoForward = wv.canGoForward }
            }
        ]
    }
}

// MARK: - Navigation / UI delegate logic (called by TabDelegate)
//
// These are plain instance methods (NOT the protocol methods) so `Tab` can stay
// a pure `ObservableObject` — the `NSObject`-requiring protocol conformance
// lives on the lightweight `TabDelegate` shim below, which forwards here.
// Inside `Tab`'s own methods we can freely write `private(set)` properties.

extension Tab {

    func decidePolicy(for navigationAction: WKNavigationAction,
                      decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Block unwanted new-window navigations unless popups are allowed.
        if navigationAction.targetFrame == nil {
            decisionHandler(context?.settings.allowsPopups ?? false ? .allow : .cancel)
            return
        }
        decisionHandler(.allow)
    }

    func decidePolicy(for navigationResponse: WKNavigationResponse,
                      decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        // Non-renderable responses become downloads (e.g. .zip, .dmg).
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }

    func didBecomeDownload(_ download: WKDownload) {
        context?.handleDownload(download)
    }

    func didStartProvisionalNavigation() {
        isLoading = true
    }

    func didFinishNavigation(in webView: WKWebView) {
        isLoading = false
        if let t = webView.title, !t.isEmpty { title = t }
        extractFavicon(from: webView)
    }

    /// Extract the favicon URL from the loaded page using JS, falling back to
    /// `host/favicon.ico`. Uses Google's favicon service as a last resort for
    /// sites that don't declare a favicon.
    private func extractFavicon(from webView: WKWebView) {
        guard let host = webView.url?.host else { return }

        // Try to read <link rel="icon" href="..."> from the page.
        let js = """
        (function() {
          var links = document.querySelectorAll('link[rel~="icon"], link[rel="shortcut icon"], link[rel="apple-touch-icon"]');
          for (var i = 0; i < links.length; i++) {
            var href = links[i].getAttribute('href');
            if (href) return href;
          }
          return null;
        })();
        """

        webView.evaluateJavaScript(js) { [weak self] result, _ in
            Task { @MainActor in
                guard let self else { return }
                if let href = result as? String, !href.isEmpty {
                    // Resolve relative URLs against the page URL.
                    if let base = webView.url, let resolved = URL(string: href, relativeTo: base) {
                        self.faviconURL = resolved.absoluteURL
                    } else if let url = URL(string: href) {
                        self.faviconURL = url
                    }
                } else {
                    // Fallback: Google's favicon service (always works, cached).
                    self.faviconURL = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64")
                }
            }
        }
    }

    func didFailNavigation(error: Error, webView: WKWebView) {
        isLoading = false
        if (error as? URLError)?.code == .cancelled { return }
        presentError(error, on: webView)
    }

    func presentError(_ error: Error, on webView: WKWebView) {
        WebDialogs.presentAlert("Couldn't load page",
                                text: (error as NSError).localizedDescription,
                                on: webView, completion: {})
    }

    // target=_blank / window.open -> a brand new tab.
    func createNewTab(for navigationAction: WKNavigationAction,
                      configuration: WKWebViewConfiguration) -> WKWebView? {
        guard context?.settings.allowsPopups ?? true else { return nil }
        return context?.requestNewTab(for: navigationAction.request, configuration: configuration)
    }
}

// MARK: - TabDelegate
//
// NSObject shim owning the WKNavigationDelegate / WKUIDelegate conformance.
// All it does is forward to the owning `Tab`; the logic + state live on `Tab`.

final class TabDelegate: NSObject, WKNavigationDelegate, WKUIDelegate {
    weak var tab: Tab?

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        tab?.decidePolicy(for: navigationAction, decisionHandler: decisionHandler)
            ?? decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        tab?.decidePolicy(for: navigationResponse, decisionHandler: decisionHandler)
            ?? decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView,
                 navigationResponse: WKNavigationResponse,
                 didBecome download: WKDownload) {
        tab?.didBecomeDownload(download)
    }

    func webView(_ webView: WKWebView,
                 navigationAction: WKNavigationAction,
                 didBecome download: WKDownload) {
        tab?.didBecomeDownload(download)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        tab?.didStartProvisionalNavigation()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        tab?.didFinishNavigation(in: webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        tab?.didFailNavigation(error: error, webView: webView)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        tab?.didFailNavigation(error: error, webView: webView)
    }

    // MARK: WKUIDelegate

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        tab?.createNewTab(for: navigationAction, configuration: configuration)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        WebDialogs.presentAlert(message, text: nil, on: webView, completion: completionHandler)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        WebDialogs.presentConfirm(message, on: webView, completion: completionHandler)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        WebDialogs.presentPrompt(prompt, defaultText: defaultText, on: webView,
                                 completion: completionHandler)
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping ([URL]?) -> Void) {
        WebDialogs.presentOpenPanel(allowsMultiple: parameters.allowsMultipleSelection,
                                    on: webView, completion: completionHandler)
    }

    // Permission prompts — privacy-first, but still ask the user.
    func webView(_ webView: WKWebView,
                 requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        WebDialogs.presentPermission(type == .microphone ? "microphone" : "camera",
                                     host: origin.host, on: webView) { allow in
            decisionHandler(allow ? .grant : .deny)
        }
    }

    func webView(_ webView: WKWebView, requestGeolocationPermissionFor frame: WKFrameInfo,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        WebDialogs.presentPermission("location",
                                     host: frame.request.url?.host ?? "site",
                                     on: webView) { allow in
            decisionHandler(allow ? .grant : .deny)
        }
    }
}
