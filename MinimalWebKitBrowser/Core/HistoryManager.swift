import Foundation
import WebKit

// MARK: - HistoryManager
//
// Keeps track of visited pages. Simple and lightweight.
// Persists to history.json in the application support directory.

struct HistoryItem: Codable, Identifiable {
    let id: UUID
    let url: String
    let title: String
    let timestamp: Date

    init(id: UUID = UUID(), url: String, title: String, timestamp: Date = Date()) {
        self.id = id
        self.url = url
        self.title = title
        self.timestamp = timestamp
    }
}

@MainActor
final class HistoryManager: ObservableObject {
    static let shared = HistoryManager()

    @Published var items: [HistoryItem] = []

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        let appDir = dir.appendingPathComponent("MinimalWebKitBrowser", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("history.json")
    }()

    private init() {
        load()
    }

    func add(url: URL, title: String) {
        // Don't add blank pages or empty titles
        guard !url.absoluteString.contains("about:blank"), !title.isEmpty else { return }

        // Remove duplicates of the same URL to keep history clean (last visit wins)
        items.removeAll { $0.url == url.absoluteString }

        let item = HistoryItem(url: url.absoluteString, title: title)
        items.insert(item, at: 0)

        // Keep only last 1000 items
        if items.count > 1000 {
            items = Array(items.prefix(1000))
        }

        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("[MWB] Failed to save history: \(error.localizedDescription)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            items = try JSONDecoder().decode([HistoryItem].self, from: data)
        } catch {
            NSLog("[MWB] Failed to load history: \(error.localizedDescription)")
        }
    }
}
