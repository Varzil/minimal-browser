import SwiftUI

// MARK: - SidebarTabs
//
// A Zen-browser-style collapsible vertical tab sidebar. Key behaviors:
//
// • Two width states: expanded (full titles, resizable) and collapsed (icon rail ~48pt).
//   Toggled by the collapse button or ⌘⌥S. Smooth spring animation.
//
// • Pinned tabs section at the top (icon-only, always visible even when collapsed).
//
// • Regular tabs list below with scroll.
//
// • New-tab button at the BOTTOM (Zen style), not the top.
//
// • Workspace switcher rail at the very bottom — icons for each workspace.
//
// • Active tab gets a Zen-style accent indicator bar on its leading edge.
//
// • In compact mode, the sidebar is hidden and revealed as a FLOATING overlay
//   when the user hovers the screen edge (doesn't push web content).

struct SidebarTabs: View {
    @ObservedObject var tabManager: TabManager
    @ObservedObject var settings: SettingsStore
    let side: SidebarSide
    let onNew: () -> Void

    // Live, non-persisted drag width; committed to settings on drag end.
    @State private var liveWidth: CGFloat?

    private var s: BrowserSettings { settings.settings }
    private var collapsed: Bool { s.sidebarCollapsed }
    private var width: CGFloat { liveWidth ?? CGFloat(s.sidebarWidth) }

    var body: some View {
        VStack(spacing: 0) {
            // Pinned tabs section (always icon-only, even when expanded)
            if !tabManager.pinnedTabs.isEmpty {
                pinnedSection
                if !collapsed { Divider().opacity(0.5) }
            }

            // Regular tabs list
            tabList

            Spacer(minLength: 0)

            // New tab button at the bottom (Zen style)
            newTabButton

            // Workspace switcher at the very bottom
            Divider().opacity(0.5)
            workspaceSwitcher
        }
        .frame(width: collapsed ? 48 : width)
        .background(sidebarBackground)
        .overlay(alignment: side.edge) { resizeHandle }
        .animation(.spring(duration: 0.3, bounce: 0), value: collapsed)
    }

    // MARK: Sidebar background (adapts to dark/light, Zen-like subtle tint)

    private var sidebarBackground: Color {
        Color(nsColor: .windowBackgroundColor)
            .opacity(0.96)
    }

    // MARK: Pinned section

    private var pinnedSection: some View {
        VStack(spacing: 2) {
            ForEach(tabManager.pinnedTabs) { tab in
                PinnedTabCell(tab: tab,
                              isSelected: tabManager.isSelected(tab),
                              onSelect: { tabManager.selectTab(tab) },
                              onClose: { tabManager.closeTab(tab) })
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, 6)
    }

    // MARK: Tab list

    private var tabList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 2) {
                ForEach(Array(tabManager.regularTabs.enumerated()), id: \.element.id) { idx, tab in
                    SidebarTabCell(
                        tab: tab,
                        isSelected: tabManager.regularTabIndex(of: tab) == tabManager.selectedIndex - tabManager.pinnedTabs.count,
                        collapsed: collapsed,
                        side: side,
                        onSelect: { tabManager.selectTab(tab) },
                        onClose: { tabManager.closeTab(tab) }
                    )
                }
            }
            .padding(.horizontal, collapsed ? 4 : 6)
            .padding(.top, 6)
            .padding(.bottom, 4)
        }
    }

    // MARK: New tab button (bottom, Zen style)

    private var newTabButton: some View {
        Button(action: onNew) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                if !collapsed {
                    Text("New Tab")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: collapsed ? .center : .leading)
            .frame(height: 30)
            .padding(.horizontal, collapsed ? 0 : 8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
        .help("New tab (⌘T)")
        .padding(.horizontal, collapsed ? 6 : 8)
        .padding(.bottom, 4)
    }

    // MARK: Workspace switcher

    private var workspaceSwitcher: some View {
        HStack(spacing: 0) {
            ForEach(tabManager.workspaces) { ws in
                Button {
                    tabManager.switchToWorkspace(ws)
                } label: {
                    Image(systemName: ws.icon)
                        .font(.system(size: 12))
                        .frame(width: collapsed ? 44 : 32, height: 30)
                        .foregroundStyle(ws.id == tabManager.activeWorkspaceId ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(ws.name)
            }
            if !collapsed {
                Spacer(minLength: 0)
                Button {
                    tabManager.addWorkspace()
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .frame(width: 28, height: 30)
                }
                .buttonStyle(.plain)
                .help("New workspace")
            }
        }
        .padding(.horizontal, collapsed ? 0 : 4)
    }

    // MARK: Resize handle (only when expanded)

    private var resizeHandle: some View {
        Group {
            if !collapsed {
                Rectangle()
                    .fill(.clear)
                    .frame(width: 6)
                    .contentShape(Rectangle())
                    .cursor(.resizeLeftRight)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let base = CGFloat(s.sidebarWidth)
                                let delta = side == .left ? value.translation.width : -value.translation.width
                                liveWidth = clampWidth(base + delta)
                            }
                            .onEnded { _ in
                                if let w = liveWidth {
                                    settings.update { $0.sidebarWidth = Int(w) }
                                }
                                liveWidth = nil
                            }
                    )
            }
        }
    }

    private func clampWidth(_ w: CGFloat) -> CGFloat {
        min(max(w, 180), 420)
    }
}

// MARK: - SidebarSide

enum SidebarSide {
    case left, right
    var edge: Alignment {
        self == .left ? .trailing : .leading
    }
}

// MARK: - SidebarTabCell (regular tab)

private struct SidebarTabCell: View {
    @ObservedObject var tab: Tab
    let isSelected: Bool
    let collapsed: Bool
    let side: SidebarSide
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: collapsed ? 0 : 8) {
            // Active-tab accent indicator on the leading edge (Zen style).
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(isSelected ? Color.accentColor : Color.clear)
                .frame(width: 2.5)

            leadingGlyph
                .frame(width: collapsed ? nil : 16)

            if !collapsed {
                Text(tab.title.isEmpty ? "New Tab" : tab.title)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                Spacer(minLength: 0)
                closeOrHover
            }
        }
        .frame(height: 32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, collapsed ? 0 : 2)
        .padding(.trailing, collapsed ? 0 : 4)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onHover { hovering = $0 }
        .onTapGesture { onSelect() }
        .help(collapsed ? (tab.title.isEmpty ? "New Tab" : tab.title) : "")
    }

    @ViewBuilder
    private var leadingGlyph: some View {
        if tab.isLoading {
            ProgressView().controlSize(.small).frame(width: 14, height: 14)
        } else if !tab.hostGlyph.isEmpty {
            Text(tab.hostGlyph)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
        } else {
            Image(systemName: "globe")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var closeOrHover: some View {
        if hovering || isSelected {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close tab (⌘W)")
            .transition(.opacity.combined(with: .scale))
        } else {
            Color.clear.frame(width: 16, height: 16)
        }
    }

    private var rowBackground: Color {
        if isSelected { return Color.accentColor.opacity(0.15) }
        return hovering ? Color.primary.opacity(0.06) : Color.clear
    }
}

// MARK: - PinnedTabCell (always icon-only)

private struct PinnedTabCell: View {
    @ObservedObject var tab: Tab
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var hovering = false

    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(isSelected ? Color.accentColor.opacity(0.15) :
                  (hovering ? Color.primary.opacity(0.06) : Color.clear))
            .frame(width: 36, height: 36)
            .overlay(
                HStack(spacing: 0) {
                    if tab.isLoading {
                        ProgressView().controlSize(.small).frame(width: 14, height: 14)
                    } else if !tab.hostGlyph.isEmpty {
                        Text(tab.hostGlyph)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    } else {
                        Image(systemName: "globe")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            )
            .overlay(alignment: .topTrailing) {
                if hovering {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .background(Circle().fill(Color(nsColor: .windowBackgroundColor)))
                    }
                    .buttonStyle(.plain)
                    .padding(2)
                    .transition(.opacity)
                }
            }
            .onHover { hovering = $0 }
            .onTapGesture { onSelect() }
            .help(tab.title.isEmpty ? "New Tab" : tab.title)
    }
}

// MARK: - Cursor helper

private extension View {
    /// Sets the cursor over this view via NSCursor (SwiftUI has no native API).
    /// Uses `.set()` (not push/pop) to avoid unbalancing the cursor stack.
    func cursor(_ cursor: NSCursor) -> some View {
        onHover { inside in
            if inside { cursor.set() } else { NSCursor.arrow.set() }
        }
    }
}
