import SwiftUI

// MARK: - BrowserWindow
//
// Zen-inspired root window layout. Key design:
//
// • No title bar — ultra-minimal chrome (windowStyle .hiddenTitleBar set at scene level).
// • Toolbar at top with nav buttons + centered address bar.
// • Thin progress bar under the toolbar.
// • Sidebar on the left (default) or right, collapsible, resizable.
// • COMPACT MODE: sidebar is hidden; hovering the screen edge reveals a
//   FLOATING sidebar overlay on top of the web content (Zen's signature feature).
//   The web content stays full-width — the sidebar floats above it.
// • Optional status bar at the bottom.

struct BrowserWindow: View {
    @ObservedObject var vm: BrowserViewModel
    @ObservedObject var settingsStore: SettingsStore

    private var s: BrowserSettings { settingsStore.settings }

    var body: some View {
        Group {
            if vm.isReady, let tab = vm.tabs.selectedTab {
                content(for: tab)
            } else {
                LaunchPlaceholder()
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .background(.windowBackground)
    }

    @ViewBuilder
    private func content(for tab: Tab) -> some View {
        VStack(spacing: 0) {
            ToolbarView(vm: vm, tab: tab, settings: s)
            ProgressBar(tab: tab)

            HStack(spacing: 0) {
                if sidebarShown(.left) {
                    SidebarTabs(tabManager: vm.tabs, settings: settingsStore,
                                side: .left, onNew: vm.newTab)
                }

                WebViewHost(tabManager: vm.tabs)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if sidebarShown(.right) {
                    SidebarTabs(tabManager: vm.tabs, settings: settingsStore,
                                side: .right, onNew: vm.newTab)
                }
            }

            if s.showStatusBar {
                Divider()
                StatusBar(tab: tab)
            }
        }
    }

    /// True only when the sidebar is enabled, visible, and on the given side.
    /// In compact mode, the sidebar is hidden (maximized content).
    private func sidebarShown(_ side: SidebarSide) -> Bool {
        guard s.sidebarVisible, !s.compactMode else { return false }
        return (s.tabPosition == .left && side == .left)
            || (s.tabPosition == .right && side == .right)
    }
}

// MARK: - ProgressBar

private struct ProgressBar: View {
    @ObservedObject var tab: Tab

    var body: some View {
        Group {
            if tab.isLoading {
                ProgressView(value: tab.estimatedProgress)
                    .progressViewStyle(.linear)
                    .frame(height: 2)
                    .tint(.accentColor)
            } else {
                Color.clear.frame(height: 0)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: tab.isLoading)
    }
}

// MARK: - StatusBar

private struct StatusBar: View {
    @ObservedObject var tab: Tab

    var body: some View {
        HStack {
            if tab.isSecure {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
            }
            Text(tab.displayURL)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .background(.bar)
    }
}

// MARK: - LaunchPlaceholder

private struct LaunchPlaceholder: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "globe.americas.fill")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
            ProgressView().controlSize(.regular)
            Text("Starting up…")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
