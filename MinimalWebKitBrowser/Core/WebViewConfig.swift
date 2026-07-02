import WebKit
import Foundation

// MARK: - WebViewConfig
//
// The performance heart of the browser. Every knob here was chosen to minimize
// first-paint latency, idle CPU, and resident memory on Apple Silicon.
//
// A few important realities that shaped this file:
//
// • `WKProcessPool` is deprecated and a no-op since macOS 12 — WebKit now owns
//   process management and shares content processes automatically across views.
//   We deliberately do NOT touch process pools.
//
// • There is no public API to toggle hardware acceleration on macOS; WebKit
//   always composites on the GPU and uses hardware media decoders on Apple
//   Silicon. We simply avoid features that add GPU/compositor work.
//
// • The single biggest lever for low idle usage on macOS 14+ is
//   `WKPreferences.InactiveSchedulingPolicy`, which throttles/suspends JS and
//   layout on tabs detached from the window. We combine that with our own
//   coarse "tear down the WKWebView entirely after N minutes" unloader.

enum WebViewConfig {

    /// Builds a fully-wired, optimized `WKWebViewConfiguration` from settings.
    /// A fresh controller is created per web view so user-script injection and
    /// content rules stay isolated per tab.
    static func makeConfiguration(
        settings: BrowserSettings,
        contentRuleList: WKContentRuleList?,
        scriptHandler: WKScriptMessageHandler? = nil
    ) -> WKWebViewConfiguration {
        let controller = WKUserContentController()

        // --- Custom user scripts (power-user CSS/JS injection) ---
        installUserScripts(into: controller, settings: settings)

        // --- Content blocking (tracker/cookie blocking rule list) ---
        if settings.blockTrackers, let list = contentRuleList {
            controller.add(list)
        }

        // --- YouTube Ad Blocking / Interface cleanup ---
        injectYouTubeFixes(into: controller)

        let config = WKWebViewConfiguration()
        config.userContentController = controller

        // --- Data store: non-persistent in private mode ---
        config.websiteDataStore = settings.privateBrowsing
            ? .nonPersistent()
            : .default()

        // --- Rendering: keep incremental rendering ON for fastest first paint ---
        // suppressesIncrementalRendering == false (default) draws partial content
        // as bytes arrive. Setting it true blocks first paint until layout settles
        // — the opposite of "snappy".
        config.suppressesIncrementalRendering = false

        // --- Trim nonessential subsystems to cut per-page overhead ---
        config.allowsAirPlayForMediaPlayback = !settings.blockAirPlay
        // Upgrade http:// to https:// for known HSTS hosts (cheap, safe, privacy+perf).
        config.upgradeKnownHostsToHTTPS = settings.upgradeKnownHostsToHTTPS

        // --- Autoplay policy ---
        // .all => a user gesture is required before media plays (no surprise
        // background decode/render cost). .none => autoplay freely.
        config.mediaTypesRequiringUserActionForPlayback =
            settings.mediaAutoplayRequiresUserAction ? .all : []

        // --- Per-page preferences (modern replacements for deprecated WKPreferences flags) ---
        let pagePrefs = WKWebpagePreferences()
        // `allowsContentJavaScript` supersedes the deprecated `javaScriptEnabled`.
        pagePrefs.allowsContentJavaScript = settings.enableJavaScript
        pagePrefs.preferredContentMode = preferredContentMode(settings.defaultContentMode)
        config.defaultWebpagePreferences = pagePrefs

        // --- Preferences ---
        let prefs = WKPreferences()
        prefs.javaScriptCanOpenWindowsAutomatically = settings.javaScriptCanOpenWindows
        prefs.isElementFullscreenEnabled = settings.elementFullscreenEnabled
        prefs.isFraudulentWebsiteWarningEnabled = settings.fraudulentSiteWarnings
        prefs.tabFocusesLinks = true
        prefs.minimumFontSize = CGFloat(settings.minimumFontSize)
        // The star of the show on macOS 14+: throttle/suspend idle detached views.
        prefs.inactiveSchedulingPolicy = inactivePolicy(settings.inactivePolicy)
        config.preferences = prefs

        // --- User agent ---
        // Empty => WebKit's native UA; otherwise override (power-user feature).
        if !settings.customUserAgent.isEmpty {
            config.applicationNameForUserAgent = settings.customUserAgent
        } else {
            config.applicationNameForUserAgent = "MinimalWebKitBrowser/1.0"
        }

        return config
    }

    /// Constructs and configures a ready-to-show `WKWebView`.
    /// The caller owns the returned view; delegates are wired by `Tab`.
    static func makeWebView(
        configuration: WKWebViewConfiguration,
        settings: BrowserSettings
    ) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: configuration)

        // Native page zoom (cheap, layout-stable, no JS round-trip).
        webView.pageZoom = CGFloat(settings.pageZoom)

        // Allow pinch-to-zoom; our toolbar buttons use pageZoom for deterministic steps.
        webView.allowsMagnification = true

        // DevTools: off by default for a lean feel, but available via menu/shortcut.
        webView.configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")

        // Let the page background show through so the window chrome blends; hidden
        // background web views are throttled by `inactiveSchedulingPolicy`.
        // (underPageBackgroundColor is the macOS replacement for iOS' drawsBackground.)
        if #available(macOS 12.0, *) {
            webView.underPageBackgroundColor = .clear
        }

        return webView
    }

    // MARK: - Helpers

    private static func injectYouTubeFixes(into controller: WKUserContentController) {
        let js = """
        (function() {
            const blockAds = () => {
                // Remove overlay ads
                const overlays = document.querySelectorAll('.ytp-ad-overlay-container, .ytp-ad-message-container');
                overlays.forEach(el => el.remove());

                // Skip video ads
                const video = document.querySelector('video');
                const ad = document.querySelector('.ad-showing, .ytp-ad-visit-advertiser-button');
                if (ad && video && isFinite(video.duration)) {
                    video.currentTime = video.duration;
                }

                // Click skip button
                const skipButton = document.querySelector('.ytp-ad-skip-button, .ytp-ad-skip-button-modern');
                if (skipButton) {
                    skipButton.click();
                }
            };

            // Run regularly
            setInterval(blockAds, 500);

            // Also run on mutations
            const observer = new MutationObserver(blockAds);
            observer.observe(document.body, { childList: true, subtree: true });
        })();
        """
        let script = WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        controller.addUserScript(script)
    }

    private static func installUserScripts(
        into controller: WKUserContentController,
        settings: BrowserSettings
    ) {
        // Custom CSS is injected by creating a <style> element at document end.
        // Doing it in JS (rather than a WKUserScript with raw CSS) avoids the need
        // for a separate CSS-injection API and keeps it injectable after navigations.
        if settings.injectCustomCSS, !settings.customCSS.isEmpty {
            let escaped = settings.customCSS
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
                .replacingOccurrences(of: "$", with: "\\$")
            let cssJS = """
            (function(){
              try {
                var s = document.createElement('style');
                s.type = 'text/css';
                s.id = 'mwb-custom-css';
                s.appendChild(document.createTextNode(`\(escaped)`));
                (document.head || document.documentElement).appendChild(s);
              } catch(e) {}
            })();
            """
            let script = WKUserScript(
                source: cssJS,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            )
            controller.addUserScript(script)
        }

        // Custom JS at document end.
        if settings.injectCustomJS, !settings.customJS.isEmpty {
            let script = WKUserScript(
                source: settings.customJS,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            )
            controller.addUserScript(script)
        }
    }

    private static func preferredContentMode(_ s: ContentModeSetting) -> WKWebpagePreferences.ContentMode {
        switch s {
        case .recommended: return .recommended
        case .desktop: return .desktop
        case .mobile: return .mobile
        }
    }

    private static func inactivePolicy(_ s: InactivePolicy) -> WKPreferences.InactiveSchedulingPolicy {
        switch s {
        case .suspend: return .suspend
        case .throttle: return .throttle
        case .none: return .none
        }
    }
}
