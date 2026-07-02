import Foundation

// MARK: - Workspace
//
// Zen-style workspace: a named, icon-tagged grouping of tabs. Each workspace
// has its own set of tabs; switching workspaces swaps the visible tab set.
// Workspaces are serialized as part of the session so they survive relaunch.

struct Workspace: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    /// SF Symbol name for the workspace icon (shown in the sidebar bottom rail).
    var icon: String
    var tabs: [TabState]
    var selectedIndex: Int

    init(id: UUID = UUID(), name: String, icon: String = "square.grid.2x2",
         tabs: [TabState] = [], selectedIndex: Int = 0) {
        self.id = id; self.name = name; self.icon = icon
        self.tabs = tabs; self.selectedIndex = selectedIndex
    }
}

// MARK: - WorkspacePresets
//
// Default workspace icons offered in the UI (matching Zen's icon picker vibe).

enum WorkspaceIcon: String, CaseIterable, Identifiable {
    case grid = "square.grid.2x2"
    case globe = "globe"
    case briefcase = "briefcase"
    case house = "house"
    case book = "book"
    case cart = "cart"
    case gamecontroller = "gamecontroller"
    case music = "music.note"
    case star = "star"
    case gear = "gearshape"
    case person = "person"
    case graduationcap = "graduationcap"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .grid: return "Default"
        case .globe: return "Web"
        case .briefcase: return "Work"
        case .house: return "Personal"
        case .book: return "Study"
        case .cart: return "Shopping"
        case .gamecontroller: return "Gaming"
        case .music: return "Music"
        case .star: return "Favorites"
        case .gear: return "Settings"
        case .person: return "Social"
        case .graduationcap: return "School"
        }
    }
}
