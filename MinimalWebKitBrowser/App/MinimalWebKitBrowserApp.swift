import SwiftUI
import AppKit
import WebKit

// MARK: - Entry Point (pure AppKit, no SwiftUI App protocol)
//
// We bypass SwiftUI's App/WindowGroup lifecycle entirely. SwiftUI's WindowGroup
// has persistent window-vanishing issues when launched outside Xcode (state
// restoration + automatic termination interactions). A manual NSWindow gives
// us full, reliable control over the window lifecycle.

@main
enum MinimalWebKitBrowserApp {
    static func main() {
        NSLog("[MWB] main() called")
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        NSLog("[MWB] about to run")
        app.run()
    }
}

// MARK: - AppDelegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var vm: BrowserViewModel?
    private var mainWindow: NSWindow?
    private var keepAliveTimer: DispatchSourceTimer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[MWB] didFinishLaunching")
        let vm = BrowserViewModel()
        self.vm = vm

        let contentView = BrowserWindow(vm: vm, settingsStore: vm.settings)
            .preferredColorScheme(colorScheme(for: vm.settings.settings.theme))

        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1100, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Minimal Browser"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = NSWindow.TitleVisibility.hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingController(rootView: contentView).view
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        mainWindow = window

        Task { @MainActor in
            await vm.bootstrap()
        }

        NSApp.activate(ignoringOtherApps: true)
        setupMenu()

        // Aggressive keep-alive: check every 0.1s and re-show the window if
        // macOS closed it. This is necessary because CLI-built apps without
        // proper code signing are aggressively managed by macOS state restoration.
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.1, repeating: 0.1)
        timer.setEventHandler { [weak self] in
            guard let self, let w = self.mainWindow else { return }
            if !w.isVisible {
                w.makeKeyAndOrderFront(nil)
                w.orderFrontRegardless()
            }
        }
        timer.resume()
        keepAliveTimer = timer
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // The window is being closed by macOS state restoration. We can't stop
        // it here, but we can immediately re-show it on the next run loop tick.
        DispatchQueue.main.async { [weak self] in
            guard let self, let w = self.mainWindow else { return }
            w.makeKeyAndOrderFront(nil)
            w.orderFrontRegardless()
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        return false
    }

    // MARK: - NSApplicationDelegate

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        vm?.saveSessionNow()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    private func colorScheme(for theme: AppTheme) -> ColorScheme? {
        switch theme {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    // MARK: - Menu bar

    private func setupMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Minimal Browser", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New Tab", action: #selector(newTab), keyEquivalent: "t").target = self
        fileMenu.addItem(withTitle: "Close Tab", action: #selector(closeTab), keyEquivalent: "w").target = self
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Reload Page", action: #selector(reload), keyEquivalent: "r").target = self
        viewMenu.addItem(withTitle: "Stop", action: #selector(stop), keyEquivalent: ".").target = self
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Go Back", action: #selector(goBack), keyEquivalent: "[").target = self
        viewMenu.addItem(withTitle: "Go Forward", action: #selector(goForward), keyEquivalent: "]").target = self
        viewMenu.addItem(withTitle: "Home", action: #selector(goHome), keyEquivalent: "h").target = self
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        let sidebarMenuItem = NSMenuItem()
        let sidebarMenu = NSMenu(title: "Sidebar")
        sidebarMenu.addItem(withTitle: "Toggle Sidebar", action: #selector(toggleSidebar), keyEquivalent: "s").keyEquivalentModifierMask = [.command, .shift]
        sidebarMenu.addItem(withTitle: "Collapse / Expand", action: #selector(toggleSidebarCollapse), keyEquivalent: "s").keyEquivalentModifierMask = [.command, .option]
        sidebarMenu.addItem(withTitle: "Cycle Sidebar Width", action: #selector(cycleSidebarWidth), keyEquivalent: "b").keyEquivalentModifierMask = [.command, .option]
        sidebarMenu.addItem(.separator())
        sidebarMenu.addItem(withTitle: "Toggle Compact Mode", action: #selector(toggleCompactMode), keyEquivalent: "c").keyEquivalentModifierMask = [.command, .option]
        for item in sidebarMenu.items where item.action != nil { item.target = self }
        sidebarMenuItem.submenu = sidebarMenu
        mainMenu.addItem(sidebarMenuItem)

        let tabMenuItem = NSMenuItem()
        let tabMenu = NSMenu(title: "Tab")
        tabMenu.addItem(withTitle: "Next Tab", action: #selector(nextTab), keyEquivalent: "]").keyEquivalentModifierMask = [.command, .shift]
        tabMenu.addItem(withTitle: "Previous Tab", action: #selector(prevTab), keyEquivalent: "[").keyEquivalentModifierMask = [.command, .shift]
        for item in tabMenu.items where item.action != nil { item.target = self }
        tabMenuItem.submenu = tabMenu
        mainMenu.addItem(tabMenuItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Menu actions

    @objc private func newTab() { vm?.newTab() }
    @objc private func closeTab() { vm?.closeCurrentTab() }
    @objc private func reload() { vm?.reload() }
    @objc private func stop() { vm?.stop() }
    @objc private func goBack() { vm?.goBack() }
    @objc private func goForward() { vm?.goForward() }
    @objc private func goHome() { vm?.goHome() }
    @objc private func nextTab() { vm?.selectNext() }
    @objc private func prevTab() { vm?.selectPrevious() }
    @objc private func toggleSidebar() { vm?.toggleSidebar() }
    @objc private func toggleSidebarCollapse() { vm?.toggleSidebarCollapse() }
    @objc private func cycleSidebarWidth() { vm?.cycleSidebarWidth() }
    @objc private func toggleCompactMode() { vm?.toggleCompactMode() }
    @objc private func openSettings() {
        let settingsView = SettingsView(store: SettingsStore.shared)
        let settingsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 480),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        settingsWindow.title = "Settings"
        settingsWindow.contentView = NSHostingController(rootView: settingsView).view
        settingsWindow.center()
        settingsWindow.makeKeyAndOrderFront(nil)
    }
}
