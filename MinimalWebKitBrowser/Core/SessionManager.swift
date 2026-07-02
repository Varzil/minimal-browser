import Foundation

// MARK: - SessionManager
//
// Persists the open tabs (`[TabState]`) to disk so the last session can be
// restored on next launch. Uses a simple JSON file under the app's support dir.
// Kept intentionally minimal — no history DB, no per-tab back-forward stacks.

@MainActor
final class SessionManager {
    static let shared = SessionManager()

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        let appDir = dir.appendingPathComponent("MinimalWebKitBrowser", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("session.json")
    }()

    func save(tabs: [TabState]) {
        do {
            let data = try JSONEncoder().encode(tabs)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("[MinimalWebKitBrowser] Failed to save session: \(error.localizedDescription)")
        }
    }

    func load() -> [TabState]? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode([TabState].self, from: data)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
