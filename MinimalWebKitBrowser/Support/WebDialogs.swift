import AppKit
import WebKit

// MARK: - WebDialogs
//
// Tiny helper that surfaces WKWebView JS panels, file-open panels and
// permission prompts using native AppKit, anchored to the web view's window.
// Keeping this in one place lets `Tab` stay focused on lifecycle/perf.

enum WebDialogs {

    /// Resolves the NSWindow to attach sheets/alerts to for a given web view.
    private static func window(for webView: WKWebView) -> NSWindow? {
        var view: NSView? = webView
        while let v = view, v.window == nil { view = v.superview }
        return view?.window ?? NSApp.keyWindow ?? NSApp.mainWindow
    }

    static func presentAlert(_ message: String, text: String?, on webView: WKWebView,
                             completion: @escaping () -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = message
        if let t = text, !t.isEmpty { alert.informativeText = t }
        alert.addButton(withTitle: "OK")
        run(alert, on: webView, completion: { _ in completion() })
    }

    static func presentConfirm(_ message: String, on webView: WKWebView,
                               completion: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        run(alert, on: webView) { resp in
            completion(resp == .alertFirstButtonReturn)
        }
    }

    static func presentPrompt(_ message: String, defaultText: String?, on webView: WKWebView,
                              completion: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        run(alert, on: webView) { resp in
            completion(resp == .alertFirstButtonReturn ? field.stringValue : nil)
        }
    }

    /// Generic yes/no permission prompt for camera/mic/geolocation.
    static func presentPermission(_ kind: String, host: String, on webView: WKWebView,
                                  completion: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\(host) wants to use your \(kind)."
        alert.informativeText = "Grant access?"
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Deny")
        run(alert, on: webView) { resp in
            completion(resp == .alertFirstButtonReturn)
        }
    }

    static func presentOpenPanel(allowsMultiple: Bool, on webView: WKWebView,
                                 completion: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = allowsMultiple
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard let win = window(for: webView) else {
            completion(nil); return
        }
        panel.beginSheetModal(for: win) { resp in
            completion(resp == .OK ? panel.urls : nil)
        }
    }

    private static func run(_ alert: NSAlert, on webView: WKWebView,
                            completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window = window(for: webView) {
            alert.beginSheetModal(for: window) { resp in completion(resp) }
        } else {
            completion(alert.runModal())
        }
    }
}
