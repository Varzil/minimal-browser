import Foundation
import Combine
import AppKit

// MARK: - BrowserViewModel
//
// The composition root. It owns the `SettingsStore` and `TabManager`, wires
// settings→tabs propagation, drives session restore on launch and session
// persistence on changes, and loads the content blocker before any tab is
// created so blocking applies from the very first navigation.

@MainActor
final class BrowserViewModel: ObservableObject {
    // Shared store: every window + the Settings scene observe the same instance,
    // so a change in any one is reflected everywhere and persisted once.
    let settings = SettingsStore.shared

    let tabs = TabManager()

    @Published private(set) var isReady = false

    private var cancellables: Set<AnyCancellable> = []

    init() {
        tabs.settingsStore = settings

        // Propagate live-affectable settings (zoom, UA) to loaded tabs.
        settings.objectWillChange
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.tabs.applyLiveSettingsToAll() }
            .store(in: &cancellables)

        // Debounced session persistence on any tab structural/selection change.
        tabs.objectWillChange
            .debounce(for: .milliseconds(800), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleSessionSave() }
            .store(in: &cancellables)

        // Belt-and-suspenders flush on quit (debounced save usually covers this).
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in self?.saveSessionNow() }
            .store(in: &cancellables)
    }

    /// Called once on launch (from the App). Loads the content blocker first so
    /// every tab created afterwards has blocking; then restores the session or
    /// opens the home/new-tab page.
    func bootstrap() async {
        await ContentBlockerManager.shared.loadIfNeeded()

        tabs.setupDefaultWorkspaces()

        if settings.settings.restoreLastSession,
           let states = SessionManager.shared.load(), !states.isEmpty {
            tabs.restore(from: states)
        } else {
            tabs.newTabFromHome()
        }
        tabs.startUnloadTimer()
        isReady = true
    }

    // MARK: Convenience commands (used by menus + toolbar)

    func newTab() { tabs.newTabFromHome() }
    func closeCurrentTab() { tabs.closeTab(at: tabs.selectedIndex) }
    func goHome() {
        guard let tab = tabs.selectedTab else { return }
        if let url = URL(string: settings.settings.homepageURL) { tab.load(url) }
    }
    func reload() { tabs.selectedTab?.reload() }
    func stop() { tabs.selectedTab?.stop() }
    func goBack() { tabs.selectedTab?.goBack() }
    func goForward() { tabs.selectedTab?.goForward() }
    func selectNext() { tabs.selectNext() }
    func selectPrevious() { tabs.selectPrevious() }

    // MARK: Sidebar (Zen-style collapsible side tabs)

    /// Toggle the sidebar visible/hidden (⌘⇧S).
    func toggleSidebar() {
        settings.update { $0.sidebarVisible.toggle() }
    }
    /// Toggle the sidebar between icon-rail (collapsed) and full width.
    func toggleSidebarCollapse() {
        settings.update { $0.sidebarCollapsed.toggle() }
    }
    /// Toggle Zen-style compact mode (floating sidebar on hover).
    func toggleCompactMode() {
        settings.update { $0.compactMode.toggle() }
    }
    /// Toggle toolbar collapse.
    func toggleToolbarCollapse() {
        settings.update { $0.toolbarCollapsed.toggle() }
    }
    /// Open settings window.
    func openSettingsWindow() {
        // This is handled by AppDelegate in this manual-window setup,
        // but we expose it here for the toolbar to call.
        NSApp.sendAction(#selector(NSApplication.delegate?.openSettings), to: nil, from: nil)
    }
    /// Cycle sidebar width between collapsed, narrow, and wide (like Zen's Alt+B).
    func cycleSidebarWidth() {
        settings.update { s in
            if s.sidebarCollapsed {
                s.sidebarCollapsed = false
                s.sidebarWidth = 230
            } else if s.sidebarWidth < 280 {
                s.sidebarWidth = 320
            } else {
                s.sidebarCollapsed = true
            }
        }
    }

    /// Navigate the active tab to text typed in the address bar.
    func navigate(activeTab: Tab?, text: String) {
        guard let tab = activeTab ?? tabs.selectedTab else { return }
        let url = URLUtils.resolve(text, searchEngineURL: settings.settings.searchEngineURL)
        if let url { tab.load(url) }
    }

    // MARK: Session persistence

    private func scheduleSessionSave() {
        // Snapshot is small (url+title per tab); encoding on main is negligible.
        SessionManager.shared.save(tabs: tabs.snapshot())
    }

    /// Flush the session immediately (called on app termination).
    func saveSessionNow() {
        SessionManager.shared.save(tabs: tabs.snapshot())
    }
}
