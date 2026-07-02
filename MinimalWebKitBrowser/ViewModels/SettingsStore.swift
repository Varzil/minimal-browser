import Foundation
import SwiftUI
import Combine
import AppKit

// MARK: - SettingsStore
//
// Bridges three things into one observable store:
//   1. In-memory `BrowserSettings` (the source of truth for the app).
//   2. A power-user JSON file at `~/.config/minimal-webkit-browser/config.json`.
//   3. SwiftUI bindings (via a typed `binding(_:)` helper).
//
// Edits flow: UI mutates `settings` -> `objectWillChange` fires -> a debounced
// task rewrites the JSON file. The decoder is resilient, so hand-editing the
// file (or adding future keys) never breaks the app.

@MainActor
final class SettingsStore: ObservableObject {

    static let shared = SettingsStore()

    @Published private(set) var settings: BrowserSettings

    /// Where the user-facing JSON config lives.
    let configURL: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".config/minimal-webkit-browser", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }()

    private var saveTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    init() {
        // Load the JSON config if present; otherwise seed defaults AND write a
        // fresh config file so power users can discover every knob immediately.
        if let data = try? Data(contentsOf: configURL),
           let decoded = try? JSONDecoder().decode(BrowserSettings.self, from: data) {
            settings = decoded
        } else {
            settings = BrowserSettings()
            persist()
        }

        // Debounced auto-save on any change. 400ms is imperceptible to the user
        // but coalesces rapid edits (e.g. typing in the CSS/UA text fields).
        objectWillChange
            .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.persist() }
            .store(in: &cancellables)
    }

    /// Type-safe binding helper for SwiftUI controls.
    /// Usage: `Toggle("Compact", isOn: store.binding(\.compactMode))`
    func binding<T>(_ keyPath: WritableKeyPath<BrowserSettings, T>) -> Binding<T> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { newValue in
                var s = self.settings
                s[keyPath: keyPath] = newValue
                self.settings = s
            }
        )
    }

    /// Apply a batch of changes in one mutation (fewer re-renders / one save).
    func update(_ transform: (inout BrowserSettings) -> Void) {
        var s = settings
        transform(&s)
        settings = s
    }

    func resetToDefaults() {
        settings = BrowserSettings()
        persist()
    }

    func persist() {
        let snapshot = settings
        let url = configURL
        // Encode off the main actor to keep typing in the CSS field buttery.
        Task.detached(priority: .utility) {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(snapshot)
                try data.write(to: url, options: .atomic)
            } catch {
                NSLog("[MinimalWebKitBrowser] Failed to write config: \(error.localizedDescription)")
            }
        }
    }

    /// Reveal the config file in Finder (wired to a Settings button).
    func revealConfig() {
        NSWorkspace.shared.activateFileViewerSelecting([configURL])
    }
}
