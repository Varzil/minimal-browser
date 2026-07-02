import WebKit
import Foundation

// MARK: - ContentBlockerManager
//
// Owns a single compiled `WKContentRuleList` built from the bundled
// `blocklist.json`. Compilation is async (WebKit parses + compiles off-main),
// so we expose the result via an async getter and publish readiness so the
// `TabManager` can attach the list to web views created *before* it was ready.
//
// We keep ONE compiled list and reuse it across every tab — compiling per-tab
// would waste CPU and memory, defeating the lightweight goal.

@MainActor
final class ContentBlockerManager: ObservableObject {
    static let shared = ContentBlockerManager()

    @Published private(set) var ruleList: WKContentRuleList?

    private let ruleListIdentifier = "com.minimalwebkit.browser.blocklist"

    func loadIfNeeded() async {
        guard ruleList == nil else { return }

        // 1. Try to reuse a previously compiled list (fast path, no recompile).
        if let cached = try? await WKContentRuleListStore.default()
            .contentRuleList(forIdentifier: ruleListIdentifier) {
            ruleList = cached
            return
        }

        // 2. Compile the bundled JSON into a rule list.
        guard let json = bundledBlocklistJSON() else { return }
        do {
            let list = try await WKContentRuleListStore.default()
                .compileContentRuleList(forIdentifier: ruleListIdentifier, encodedContentRuleList: json)
            ruleList = list
        } catch {
            // A malformed list throws; we log and silently skip so browsing
            // still works (just without blocking). The bundled list is vetted.
            NSLog("[MinimalWebKitBrowser] Content rule list compile failed: \(error.localizedDescription)")
        }
    }

    private func bundledBlocklistJSON() -> String? {
        // The DefaultContentBlocker folder is copied as a folder reference.
        guard let url = Bundle.main.url(forResource: "blocklist", withExtension: "json",
                                        subdirectory: "DefaultContentBlocker")
                ?? Bundle.main.url(forResource: "blocklist", withExtension: "json") else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
