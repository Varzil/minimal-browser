import WebKit
import Foundation

// MARK: - TabManager
//
// Owns the ordered list of tabs, the active selection, and — critically — the
// *unloading policy* that keeps memory low. It is the `TabContext` for every
// tab, so it is the single chokepoint through which new tabs and downloads flow.
//
// Zen-style additions:
// • Pinned tabs (essentials) — a separate section at the top of the sidebar.
// • Workspaces — each workspace has its own tab set; switching swaps them.
//
// Design notes:
// • Newly created background tabs are LAZY (no WKWebView until shown).
// • Only the selected tab is force-loaded on restore, so cold start is instant.
// • A cooperative `Task` loop periodically unloads stale background web views.

@MainActor
final class TabManager: ObservableObject, TabContext {

    @Published private(set) var tabs: [Tab] = []
    @Published var selectedIndex: Int = 0 {
        didSet {
            guard selectedIndex >= 0, selectedIndex < tabs.count else { return }
            tabs[selectedIndex].lastActiveDate = Date()
        }
    }

    // MARK: Workspaces (Zen-style)

    @Published private(set) var workspaces: [Workspace] = []
    @Published var activeWorkspaceId: UUID = UUID()

    /// Bumped when a new tab is created and the address bar should auto-focus.
    /// The AddressBar observes this via `.onChange` and sets `focused = true`.
    @Published var focusAddressBarRequest: Int = 0

    /// Weak to avoid a cycle: the view model owns both the store and this manager.
    weak var settingsStore: SettingsStore?

    private var unloadTask: Task<Void, Never>?

    var selectedTab: Tab? {
        guard selectedIndex >= 0, selectedIndex < tabs.count else { return nil }
        return tabs[selectedIndex]
    }

    // MARK: Computed tab groups (for the sidebar)

    var pinnedTabs: [Tab] { tabs.filter { $0.isPinned } }
    var regularTabs: [Tab] { tabs.filter { !$0.isPinned } }

    func isSelected(_ tab: Tab) -> Bool {
        selectedTab?.id == tab.id
    }

    func regularTabIndex(of tab: Tab) -> Int? {
        regularTabs.firstIndex(where: { $0.id == tab.id })
    }

    // MARK: TabContext

    var settings: BrowserSettings { settingsStore?.settings ?? BrowserSettings() }
    var contentRuleList: WKContentRuleList? { ContentBlockerManager.shared.ruleList }

    func requestNewTab(for request: URLRequest, configuration: WKWebViewConfiguration?) -> WKWebView? {
        let tab = Tab(url: request.url, context: self)
        tabs.append(tab)
        selectedIndex = tabs.count - 1
        // Materialize + load synchronously so the opener gets a real WKWebView.
        let wv = tab.loadIfNeeded()
        if request.url != nil { wv.load(request) }
        return wv
    }

    func handleDownload(_ download: WKDownload) {
        DownloadManager.shared.attach(download)
    }

    // MARK: Tab CRUD

    @discardableResult
    func addTab(url: URL? = nil, select: Bool = true, pinned: Bool = false) -> Tab {
        let tab = Tab(url: url, context: self, isPinned: pinned)
        if pinned {
            // Insert pinned tabs at the beginning
            tabs.insert(tab, at: 0)
            if select { selectedIndex = 0 }
        } else {
            tabs.append(tab)
            if select { selectedIndex = tabs.count - 1 }
        }
        return tab
    }

    /// New tab rooted at the configured home/new-tab URL.
    /// Triggers the address bar to auto-focus so the user can type immediately.
    func newTabFromHome(select: Bool = true) {
        let s = settings
        if s.newTabPageURL.isEmpty {
            addTab(url: nil, select: select)              // local blank page
        } else if let url = URL(string: s.newTabPageURL) {
            addTab(url: url, select: select)
        } else {
            addTab(url: URL(string: s.homepageURL), select: select)
        }
        if select { focusAddressBarRequest += 1 }
    }

    func closeTab(at index: Int) {
        guard index >= 0, index < tabs.count else { return }
        tabs[index].unload()
        tabs.remove(at: index)

        if tabs.isEmpty {
            newTabFromHome()
            return
        }
        if selectedIndex >= tabs.count { selectedIndex = tabs.count - 1 }
        _ = selectedTab?.loadIfNeeded()
    }

    func closeTab(_ tab: Tab) {
        if let idx = tabs.firstIndex(where: { $0.id == tab.id }) { closeTab(at: idx) }
    }

    func selectTab(at index: Int) {
        guard index >= 0, index < tabs.count else { return }
        selectedIndex = index
    }

    func selectTab(_ tab: Tab) {
        if let idx = tabs.firstIndex(where: { $0.id == tab.id }) { selectedIndex = idx }
    }

    func selectNext() { selectedIndex = (selectedIndex + 1) % max(tabs.count, 1) }
    func selectPrevious() { selectedIndex = (selectedIndex - 1 + max(tabs.count, 1)) % max(tabs.count, 1) }

    func togglePinned(_ tab: Tab) {
        if let idx = tabs.firstIndex(where: { $0.id == tab.id }) {
            tabs[idx].isPinned.toggle()
            // Re-sort: pinned first, then regular
            tabs.sort { $0.isPinned && !$1.isPinned }
            if let newIdx = tabs.firstIndex(where: { $0.id == tab.id }) {
                selectedIndex = newIdx
            }
            objectWillChange.send()
        }
    }

    // MARK: Workspaces

    func setupDefaultWorkspaces() {
        if workspaces.isEmpty {
            let defaultWS = Workspace(name: "Default", icon: "square.grid.2x2")
            workspaces = [defaultWS]
            activeWorkspaceId = defaultWS.id
        }
    }

    func addWorkspace(name: String = "New Workspace", icon: String = "square.grid.2x2") {
        let ws = Workspace(name: name, icon: icon)
        workspaces.append(ws)
        switchToWorkspace(ws)
    }

    func switchToWorkspace(_ ws: Workspace) {
        // Save current tabs into the current workspace
        if let idx = workspaces.firstIndex(where: { $0.id == activeWorkspaceId }) {
            workspaces[idx].tabs = snapshot()
            workspaces[idx].selectedIndex = selectedIndex
        }

        activeWorkspaceId = ws.id

        // Load the target workspace's tabs
        if let idx = workspaces.firstIndex(where: { $0.id == ws.id }) {
            // Unload all current web views before swapping
            for tab in tabs { tab.unload() }
            tabs.removeAll()

            let states = workspaces[idx].tabs
            if states.isEmpty {
                newTabFromHome()
            } else {
                restore(from: states)
            }
        }
    }

    // MARK: Unload policy

    func startUnloadTimer() {
        unloadTask?.cancel()
        let interval = max(15, settings.unloadCheckIntervalSeconds)
        unloadTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
                guard let self else { return }
                self.runUnloadPass()
            }
        }
    }

    func stopUnloadTimer() { unloadTask?.cancel(); unloadTask = nil }

    func runUnloadPass() {
        let s = settings
        let now = Date()
        let selectedID = selectedTab?.id
        var changed = false

        let unloadSeconds = Double(s.tabUnloadMinutes * 60)
        if unloadSeconds > 0 {
            for tab in tabs where tab.isLoaded && tab.id != selectedID && !tab.isPinned {
                if now.timeIntervalSince(tab.lastActiveDate) >= unloadSeconds {
                    tab.unload(); changed = true
                }
            }
        }

        if s.maxLoadedTabs > 0 {
            let selectedLoaded = (selectedTab?.isLoaded ?? false) ? 1 : 0
            let pinnedLoaded = pinnedTabs.filter { $0.isLoaded }.count
            let allowedBackground = max(0, s.maxLoadedTabs - selectedLoaded - pinnedLoaded)
            let loaded = regularTabs
                .filter { $0.isLoaded && $0.id != selectedID }
                .sorted { $0.lastActiveDate < $1.lastActiveDate }
            let excess = loaded.count - allowedBackground
            if excess > 0 {
                for tab in loaded.prefix(excess) { tab.unload(); changed = true }
            }
        }

        if changed { objectWillChange.send() }
    }

    func applyLiveSettingsToAll() {
        let s = settings
        for tab in tabs where tab.isLoaded { tab.applyLiveSettings(s) }
    }

    // MARK: Session

    func snapshot() -> [TabState] {
        tabs.enumerated().map { i, tab in
            TabState(id: tab.id,
                     url: tab.pendingURL?.absoluteString ?? "",
                     title: tab.title,
                     isSelected: i == selectedIndex,
                     isPinned: tab.isPinned)
        }
    }

    func restore(from states: [TabState]) {
        tabs.removeAll()
        // Sort: pinned first
        let sorted = states.sorted { $0.isPinned && !$1.isPinned }
        for state in sorted {
            let url = state.url.isEmpty ? nil : URL(string: state.url)
            let tab = Tab(id: state.id, url: url, title: state.title, context: self, isPinned: state.isPinned)
            tabs.append(tab)
        }
        if tabs.isEmpty { newTabFromHome(); return }
        selectedIndex = sorted.firstIndex(where: { $0.isSelected }) ?? 0
        _ = selectedTab?.loadIfNeeded()
    }
}
