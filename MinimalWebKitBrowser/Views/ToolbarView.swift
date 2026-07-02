import SwiftUI

// MARK: - ToolbarView
//
// Zen-inspired minimal toolbar. Two states:
//   • Expanded: full nav buttons (back/forward/reload/home) + address bar + actions
//   • Collapsed: only the address bar + a toggle button (Zen "hide toolbar" style)
//
// The address bar is always visible and is the visual centerpiece.

struct ToolbarView: View {
    @ObservedObject var vm: BrowserViewModel
    @ObservedObject var tab: Tab
    let settings: BrowserSettings

    var body: some View {
        HStack(spacing: 6) {
            // Nav buttons — hidden when toolbar is collapsed
            if !settings.toolbarCollapsed {
                navButton("chevron.left", help: "Back", action: tab.goBack, disabled: !tab.canGoBack)
                navButton("chevron.right", help: "Forward", action: tab.goForward, disabled: !tab.canGoForward)

                if settings.showReloadButton {
                    navButton(tab.isLoading ? "xmark" : "arrow.clockwise",
                              help: tab.isLoading ? "Stop (⌘.)" : "Reload (⌘R)",
                              action: tab.isLoading ? tab.stop : tab.reload)
                }

                if settings.showHomeButton {
                    navButton("house", help: "Home", action: vm.goHome)
                }
            }

            // Address bar — always visible, even when toolbar is collapsed
            AddressBar(tab: tab,
                       onSubmit: { vm.navigate(activeTab: tab, text: $0) },
                       focusTrigger: vm.tabs.focusAddressBarRequest)
                .frame(maxWidth: .infinity)

            // Right-side actions — always visible
            if !settings.toolbarCollapsed {
                navButton(settings.sidebarCollapsed ? "sidebar.left" : "sidebar.left",
                          help: settings.sidebarCollapsed ? "Expand sidebar (⌘⌥S)" : "Collapse sidebar (⌘⌥S)",
                          action: vm.toggleSidebarCollapse)
            }

            navButton("plus", help: "New tab (⌘T)", action: vm.newTab)

            // Toolbar collapse/expand toggle
            navButton(settings.toolbarCollapsed ? "chevron.down" : "chevron.up",
                      help: settings.toolbarCollapsed ? "Show toolbar" : "Hide toolbar",
                      action: vm.toggleToolbarCollapse)

            navButton("slider.horizontal.3", help: "Settings (⌘,)", action: vm.openSettingsWindow)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, settings.toolbarCollapsed ? 3 : 5)
        .background(.bar)
        .animation(.easeInOut(duration: 0.2), value: settings.toolbarCollapsed)
    }

    @ViewBuilder
    private func navButton(_ icon: String, help: String, action: @escaping () -> Void,
                           disabled: Bool = false) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .regular))
                .frame(width: 24, height: 24)
                .foregroundStyle(disabled ? .tertiary : .secondary)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
    }
}
