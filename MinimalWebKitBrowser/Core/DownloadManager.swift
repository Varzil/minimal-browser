import WebKit
import Foundation
import AppKit

// MARK: - DownloadManager
//
// Implements `WKDownloadDelegate` and saves files to the user's Downloads
// folder. Kept as a tiny singleton so any tab's download lands in one place;
// a `@Published` list enables a (future) downloads popover without extra plumbing.

@MainActor
final class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()

    struct DownloadItem: Identifiable {
        let id = UUID()
        let filename: String
        let url: URL
        var progress: Double
        var isFinished: Bool
        var error: String?
    }

    @Published private(set) var items: [DownloadItem] = []
    /// Strong refs to live downloads + their Progress observer.
    private var live: [UUID: (WKDownload, Progress, NSKeyValueObservation)] = [:]

    func attach(_ download: WKDownload) {
        download.delegate = self
    }

    private func downloadsDirectory() -> URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Downloads")
    }

    /// Append " (n)" before the extension until the name is unique.
    private func uniqueDestination(filename: String) -> URL {
        let dir = downloadsDirectory()
        let proposed = dir.appendingPathComponent(filename)
        guard !FileManager.default.fileExists(atPath: proposed.path) else {
            let ext = (filename as NSString).pathExtension
            let base = (filename as NSString).deletingPathExtension
            var n = 1
            while true {
                let name = ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
                let url = dir.appendingPathComponent(name)
                if !FileManager.default.fileExists(atPath: url.path) { return url }
                n += 1
            }
        }
        return proposed
    }
}

extension DownloadManager: WKDownloadDelegate {

    func download(_ download: WKDownload,
                  decideDestinationUsing response: URLResponse,
                  suggestedFilename: String,
                  completionHandler: @escaping (URL?) -> Void) {
        let filename = suggestedFilename.isEmpty ? "download" : suggestedFilename
        let dest = uniqueDestination(filename: filename)

        let itemID = UUID()
        let item = DownloadItem(filename: filename, url: dest, progress: 0,
                                isFinished: false, error: nil)
        items.append(item)

        // Observe progress (WKDownload conforms to NSProgressReporting).
        let progress = download.progress
        let obs = progress.observe(\.fractionCompleted, options: [.new, .initial]) {
            [weak self] p, _ in
            Task { @MainActor in
                guard let self else { return }
                if let idx = self.items.firstIndex(where: { $0.id == itemID }) {
                    self.items[idx].progress = p.fractionCompleted
                }
            }
        }
        live[itemID] = (download, progress, obs)
        completionHandler(dest)
    }

    func download(_ download: WKDownload,
                  willPerformHTTPRedirection response: HTTPURLResponse,
                  newRequest request: URLRequest,
                  decisionHandler: @escaping (WKDownload.RedirectPolicy) -> Void) {
        decisionHandler(.allow)
    }

    func download(_ download: WKDownload,
                  didReceive challenge: URLAuthenticationChallenge,
                  completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Defer to the system for default handling (no credential UI here).
        completionHandler(.performDefaultHandling, nil)
    }

    func downloadDidFinish(_ download: WKDownload) {
        if let pair = live.first(where: { $0.value.0 === download }) {
            if let idx = items.firstIndex(where: { $0.id == pair.key }) {
                items[idx].isFinished = true
                items[idx].progress = 1.0
            }
            pair.value.2.invalidate()
            live.removeValue(forKey: pair.key)
        }
        // Reveal the most recent finished download in Finder (subtle, optional).
        if let last = items.last(where: { $0.isFinished }) {
            NSWorkspace.shared.activateFileViewerSelecting([last.url])
        }
    }

    func download(_ download: WKDownload,
                  didFailWithError error: Error,
                  resumeData: Data?) {
        if let pair = live.first(where: { $0.value.0 === download }) {
            if let idx = items.firstIndex(where: { $0.id == pair.key }) {
                items[idx].error = error.localizedDescription
            }
            pair.value.2.invalidate()
            live.removeValue(forKey: pair.key)
        }
    }
}
