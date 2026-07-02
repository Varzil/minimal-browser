import Foundation

// MARK: - URLUtils
//
// Turns arbitrary address-bar text into either a real URL or a search URL.
// Kept dependency-free and fast; no history DB, no network — just heuristics.

enum URLUtils {

    /// Resolve typed text into a navigable URL.
    /// - "apple.com"        -> https://apple.com
    /// - "https://..."      -> as-is
    /// - "localhost:3000"   -> http://localhost:3000
    /// - "256.256.256.256"  -> treated as a search (not a valid IP/host)
    /// - anything else      -> search via `searchEngineURL` (`%@` replaced)
    static func resolve(_ text: String, searchEngineURL: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Already a valid absolute URL? Trust it.
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
           ["http", "https", "file", "about", "data"].contains(scheme) {
            return url
        }

        // Looks like "host.tld" or "host.tld/path" with no scheme.
        if looksLikeHost(trimmed) {
            return URL(string: "https://" + trimmed)
        }

        // Localhost / IP[:port].
        if looksLikeLocalAddress(trimmed) {
            return URL(string: "http://" + trimmed)
        }

        // Otherwise: search.
        let encoded = trimmed.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        let template = searchEngineURL.contains("%@")
            ? searchEngineURL
            : "https://duckduckgo.com/?q=%@"   // fallback if config is malformed
        return URL(string: template.replacingOccurrences(of: "%@", with: encoded))
    }

    /// True if the string has a dotted domain suffix with no spaces.
    private static func looksLikeHost(_ s: String) -> Bool {
        guard s.contains(".") && !s.contains(" ") else { return false }
        let host = s.split(separator: "/").first.map(String.init) ?? s
        // Require a TLD of 2+ alpha chars.
        let parts = host.split(separator: ".")
        guard let last = parts.last, last.count >= 2, last.allSatisfy(\.isLetter) else {
            return false
        }
        return true
    }

    private static func looksLikeLocalAddress(_ s: String) -> Bool {
        let lower = s.lowercased()
        return lower.hasPrefix("localhost") || lower.hasPrefix("127.0.0.1") || lower.hasPrefix("0.0.0.0") || lower.hasPrefix("[::1]")
    }

    /// Pretty-print a URL for the address bar (strip scheme + trailing slash).
    static func displayString(for url: URL?) -> String {
        guard let url = url else { return "" }
        var s = url.absoluteString
        if let scheme = url.scheme {
            s = s.replacingOccurrences(of: "\(scheme)://", with: "")
        }
        if s.hasSuffix("/") { s.removeLast() }
        return s
    }

    /// The leading character of the host, for a cheap favicon-free tab glyph.
    static func hostGlyph(for url: URL?) -> String {
        guard let host = url?.host else { return "" }
        return String(host.prefix(1)).uppercased()
    }
}
