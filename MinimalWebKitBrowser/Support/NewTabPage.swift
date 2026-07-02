import WebKit
import Foundation

// MARK: - NewTabPage
//
// Renders a featherweight local "blank" page when `newTabPageURL` is empty.
// Generated in-memory (no asset to load) and themed to match the system
// appearance so it feels native without shipping any HTML resources.

enum NewTabPage {
    static func html(dark: Bool) -> String {
        let bg = dark ? "#1c1c1e" : "#ffffff"
        let fg = dark ? "#8e8e93" : "#c7c7cc"
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="color-scheme" content="\(dark ? "dark" : "light")">
        <style>
          html,body{height:100%;margin:0}
          body{background:\(bg);color:\(fg);font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text",system-ui,sans-serif;
               display:flex;align-items:center;justify-content:center;font-size:15px;letter-spacing:.02em}
        </style></head><body><div>Minimal Browser</div></body></html>
        """
    }

    /// Load a true new-tab page into the given web view (local, no network).
    static func load(into webView: WKWebView, dark: Bool) {
        webView.loadHTMLString(html(dark: dark), baseURL: nil)
    }
}
