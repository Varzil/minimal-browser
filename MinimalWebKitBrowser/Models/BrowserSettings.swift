import Foundation

// MARK: - BrowserSettings
//
// The single source of truth for every user-tunable knob in the browser.
// It is `Codable` so it can be (a) persisted to the JSON config file at
// `~/.config/minimal-webkit-browser/config.json` and (b) loaded back, with
// any *missing* keys falling back to these defaults (forward/backward
// compatible — adding a setting never breaks an old config file).

// Side-tab placement. Horizontal top/bottom tab bars are intentionally NOT
// offered — this browser uses a Zed-style collapsible vertical sidebar only.
// `hidden` keeps the sidebar off entirely (pure compact browsing).
enum TabPosition: String, Codable, CaseIterable, Identifiable {
    case left, right, hidden
    var id: String { rawValue }
    var label: String {
        switch self {
        case .left: return "Left sidebar"
        case .right: return "Right sidebar"
        case .hidden: return "Hidden (no sidebar)"
        }
    }
}

enum AppTheme: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

/// How an inactive (background / detached) web view is treated.
/// Maps 1:1 to `WKPreferences.InactiveSchedulingPolicy` (macOS 14+).
enum InactivePolicy: String, Codable, CaseIterable, Identifiable {
    /// Fully pause JS + layout on idle tabs. Lowest CPU/RAM, tiny wake cost.
    case suspend
    /// CPU-throttle idle tabs but keep them warm. Snappy switch, moderate savings.
    case throttle
    /// Keep idle tabs running at full speed. Most power, zero wake latency.
    case none
    var id: String { rawValue }
    var label: String {
        switch self {
        case .suspend: return "Suspend (max savings)"
        case .throttle: return "Throttle (balanced)"
        case .none: return "None (max responsiveness)"
        }
    }
}

enum ContentModeSetting: String, Codable, CaseIterable, Identifiable {
    case recommended, desktop, mobile
    var id: String { rawValue }
    var label: String {
        switch self {
        case .recommended: return "Recommended"
        case .desktop: return "Desktop"
        case .mobile: return "Mobile"
        }
    }
}

struct BrowserSettings: Codable {
    // --- Startup / session ---
    var homepageURL: String = "https://duckduckgo.com"
    /// `%@` is replaced with the URL-encoded query for keyword searches.
    var searchEngineURL: String = "https://duckduckgo.com/?q=%@&ia=web"
    /// Empty string => a true blank "speed dial" page rendered locally.
    var newTabPageURL: String = ""
    var restoreLastSession: Bool = true

    // --- Performance (the core of the "snappy" promise) ---
    /// Minutes of inactivity before a background tab's WKWebView is torn down.
    /// 0 = never unload (rely only on `inactivePolicy` throttling).
    var tabUnloadMinutes: Int = 15
    var unloadCheckIntervalSeconds: Int = 60
    /// Hard cap on simultaneously *loaded* (live WKWebView) tabs. 0 = unlimited.
    /// When exceeded, the least-recently-active loaded tab is unloaded first.
    var maxLoadedTabs: Int = 12
    var inactivePolicy: InactivePolicy = .throttle

    // --- UI ---
    /// Zen-style compact mode: hides sidebar entirely; hovering the screen edge
    /// reveals a floating sidebar overlay (doesn't push web content).
    var compactMode: Bool = false
    /// Sidebar tab placement (vertical only — left or right). No horizontal bar.
    var tabPosition: TabPosition = .left
    /// Whether the sidebar is shown at all (toggle with ⌘⇧S).
    var sidebarVisible: Bool = true
    /// Collapsed => icon-only rail (~48pt). Expanded => full width with titles.
    var sidebarCollapsed: Bool = false
    /// Expanded sidebar width in points; user-resizable via a drag handle.
    var sidebarWidth: Int = 230
    /// Collapsed toolbar hides nav buttons; only the address bar remains.
    var toolbarCollapsed: Bool = false
    var showHomeButton: Bool = true
    var showReloadButton: Bool = true
    var showStatusBar: Bool = false
    /// Show website favicons in the sidebar instead of letter glyphs.
    var showFavicons: Bool = true
    var theme: AppTheme = .system
    /// Page zoom as a multiplier (1.0 = 100%). Cheap, native zoom (no reflow cost).
    var pageZoom: Double = 1.0
    var minimumFontSize: Int = 0          // 0 = disabled

    // --- Web content / privacy ---
    var enableJavaScript: Bool = true
    var javaScriptCanOpenWindows: Bool = false
    var allowsPopups: Bool = false
    var blockTrackers: Bool = true        // compiles + applies the content rule list
    var upgradeKnownHostsToHTTPS: Bool = true
    var privateBrowsing: Bool = false
    var fraudulentSiteWarnings: Bool = true
    var defaultContentMode: ContentModeSetting = .recommended
    var mediaAutoplayRequiresUserAction: Bool = true
    var blockAirPlay: Bool = true         // skip media routing discovery overhead

    // --- Power-user customization ---
    var customUserAgent: String = ""      // empty => WebKit default
    var injectCustomCSS: Bool = false
    var customCSS: String = ""
    var injectCustomJS: Bool = false
    var customJS: String = ""
    var elementFullscreenEnabled: Bool = true

    // MARK: Codable with resilient defaults
    //
    // A custom `init(from:)` uses `decodeIfPresent` for every field so a partial
    // or outdated config.json still loads, filling gaps with `BrowserSettings()`.
    private enum CodingKeys: String, CodingKey {
        case homepageURL, searchEngineURL, newTabPageURL, restoreLastSession
        case tabUnloadMinutes, unloadCheckIntervalSeconds, maxLoadedTabs, inactivePolicy
        case compactMode, tabPosition, sidebarVisible, sidebarCollapsed, sidebarWidth, toolbarCollapsed, showHomeButton, showReloadButton, showStatusBar, showFavicons, theme, pageZoom, minimumFontSize
        case enableJavaScript, javaScriptCanOpenWindows, allowsPopups, blockTrackers, upgradeKnownHostsToHTTPS, privateBrowsing, fraudulentSiteWarnings, defaultContentMode, mediaAutoplayRequiresUserAction, blockAirPlay
        case customUserAgent, injectCustomCSS, customCSS, injectCustomJS, customJS, elementFullscreenEnabled
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func dec<T: Decodable>(_ key: CodingKeys, _ default: T) -> T {
            (try? c.decode(T.self, forKey: key)) ?? `default`
        }
        homepageURL              = dec(.homepageURL, "https://duckduckgo.com")
        searchEngineURL          = dec(.searchEngineURL, "https://duckduckgo.com/?q=%@&ia=web")
        newTabPageURL            = dec(.newTabPageURL, "")
        restoreLastSession       = dec(.restoreLastSession, true)
        tabUnloadMinutes         = dec(.tabUnloadMinutes, 15)
        unloadCheckIntervalSeconds = dec(.unloadCheckIntervalSeconds, 60)
        maxLoadedTabs            = dec(.maxLoadedTabs, 12)
        inactivePolicy           = dec(.inactivePolicy, .throttle)
        compactMode              = dec(.compactMode, false)
        tabPosition              = dec(.tabPosition, .left)
        sidebarVisible           = dec(.sidebarVisible, true)
        sidebarCollapsed         = dec(.sidebarCollapsed, false)
        sidebarWidth             = dec(.sidebarWidth, 230)
        toolbarCollapsed         = dec(.toolbarCollapsed, false)
        showHomeButton           = dec(.showHomeButton, true)
        showReloadButton         = dec(.showReloadButton, true)
        showStatusBar            = dec(.showStatusBar, false)
        showFavicons             = dec(.showFavicons, true)
        theme                    = dec(.theme, .system)
        pageZoom                 = dec(.pageZoom, 1.0)
        minimumFontSize          = dec(.minimumFontSize, 0)
        enableJavaScript         = dec(.enableJavaScript, true)
        javaScriptCanOpenWindows = dec(.javaScriptCanOpenWindows, false)
        allowsPopups             = dec(.allowsPopups, false)
        blockTrackers            = dec(.blockTrackers, true)
        upgradeKnownHostsToHTTPS = dec(.upgradeKnownHostsToHTTPS, true)
        privateBrowsing          = dec(.privateBrowsing, false)
        fraudulentSiteWarnings   = dec(.fraudulentSiteWarnings, true)
        defaultContentMode       = dec(.defaultContentMode, .recommended)
        mediaAutoplayRequiresUserAction = dec(.mediaAutoplayRequiresUserAction, true)
        blockAirPlay             = dec(.blockAirPlay, true)
        customUserAgent          = dec(.customUserAgent, "")
        injectCustomCSS          = dec(.injectCustomCSS, false)
        customCSS                = dec(.customCSS, "")
        injectCustomJS           = dec(.injectCustomJS, false)
        customJS                 = dec(.customJS, "")
        elementFullscreenEnabled = dec(.elementFullscreenEnabled, true)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(homepageURL, forKey: .homepageURL)
        try c.encode(searchEngineURL, forKey: .searchEngineURL)
        try c.encode(newTabPageURL, forKey: .newTabPageURL)
        try c.encode(restoreLastSession, forKey: .restoreLastSession)
        try c.encode(tabUnloadMinutes, forKey: .tabUnloadMinutes)
        try c.encode(unloadCheckIntervalSeconds, forKey: .unloadCheckIntervalSeconds)
        try c.encode(maxLoadedTabs, forKey: .maxLoadedTabs)
        try c.encode(inactivePolicy, forKey: .inactivePolicy)
        try c.encode(compactMode, forKey: .compactMode)
        try c.encode(tabPosition, forKey: .tabPosition)
        try c.encode(sidebarVisible, forKey: .sidebarVisible)
        try c.encode(sidebarCollapsed, forKey: .sidebarCollapsed)
        try c.encode(sidebarWidth, forKey: .sidebarWidth)
        try c.encode(toolbarCollapsed, forKey: .toolbarCollapsed)
        try c.encode(showHomeButton, forKey: .showHomeButton)
        try c.encode(showReloadButton, forKey: .showReloadButton)
        try c.encode(showStatusBar, forKey: .showStatusBar)
        try c.encode(showFavicons, forKey: .showFavicons)
        try c.encode(theme, forKey: .theme)
        try c.encode(pageZoom, forKey: .pageZoom)
        try c.encode(minimumFontSize, forKey: .minimumFontSize)
        try c.encode(enableJavaScript, forKey: .enableJavaScript)
        try c.encode(javaScriptCanOpenWindows, forKey: .javaScriptCanOpenWindows)
        try c.encode(allowsPopups, forKey: .allowsPopups)
        try c.encode(blockTrackers, forKey: .blockTrackers)
        try c.encode(upgradeKnownHostsToHTTPS, forKey: .upgradeKnownHostsToHTTPS)
        try c.encode(privateBrowsing, forKey: .privateBrowsing)
        try c.encode(fraudulentSiteWarnings, forKey: .fraudulentSiteWarnings)
        try c.encode(defaultContentMode, forKey: .defaultContentMode)
        try c.encode(mediaAutoplayRequiresUserAction, forKey: .mediaAutoplayRequiresUserAction)
        try c.encode(blockAirPlay, forKey: .blockAirPlay)
        try c.encode(customUserAgent, forKey: .customUserAgent)
        try c.encode(injectCustomCSS, forKey: .injectCustomCSS)
        try c.encode(customCSS, forKey: .customCSS)
        try c.encode(injectCustomJS, forKey: .injectCustomJS)
        try c.encode(customJS, forKey: .customJS)
        try c.encode(elementFullscreenEnabled, forKey: .elementFullscreenEnabled)
    }
}

// MARK: - TabState
//
// A featherweight, serializable snapshot of a tab used for:
//   • session restore on launch, and
//   • keeping a tab's identity alive after its WKWebView is *unloaded*
//     (so switching back to it can recreate the view & reload cheaply).
struct TabState: Codable, Identifiable, Equatable {
    var id: UUID
    var url: String
    var title: String
    var isSelected: Bool
    var isPinned: Bool

    init(id: UUID = UUID(), url: String, title: String = "", isSelected: Bool = false, isPinned: Bool = false) {
        self.id = id; self.url = url; self.title = title; self.isSelected = isSelected; self.isPinned = isPinned
    }
}
