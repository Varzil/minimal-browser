import SwiftUI
import WebKit
import AppKit

// MARK: - WebViewHost
//
// The single biggest snappiness lever in the UI layer.
//
// Instead of creating a fresh NSViewRepresentable (and thus a fresh WKWebView)
// for the active tab on every selection change, we use ONE persistent container
// NSView that simply reparents + shows the active tab's existing WKWebView.
// Background tabs keep their live web views mounted (hidden), so switching tabs
// is a sub-millisecond show/hide — no navigation, no process wake, no reload.
//
// Torn-down (unloaded) tabs materialize their web view lazily on first show.

final class WebViewContainerView: NSView {
    var currentTab: Tab? {
        didSet {
            if currentTab === oldValue { return }
            // Keep the previously shown web view mounted but hidden so a switch
            // back is instant.
            if let prev = oldValue?.webView { prev.isHidden = true }
            if let tab = currentTab {
                tab.loadIfNeeded()                 // lazy materialization
                if let wv = tab.webView {
                    wv.isHidden = false
                    // (Re)parent + raise to top in one move.
                    wv.removeFromSuperview()
                    addSubview(wv)
                }
            }
            needsLayout = true
        }
    }

    override func layout() {
        super.layout()
        // Every hosted web view fills the container.
        for sv in subviews where sv is WKWebView { sv.frame = bounds }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        needsLayout = true
    }
}

struct WebViewHost: NSViewRepresentable {
    @ObservedObject var tabManager: TabManager

    func makeNSView(context: Context) -> WebViewContainerView {
        let v = WebViewContainerView()
        // Layer-backed: the show/hide swap is GPU-composited and tear-free.
        v.wantsLayer = true
        v.currentTab = tabManager.selectedTab
        return v
    }

    func updateNSView(_ nsView: WebViewContainerView, context: Context) {
        nsView.currentTab = tabManager.selectedTab
    }
}
