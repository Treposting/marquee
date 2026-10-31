import Foundation

/// Finds the web and email links in text recognized by Copy Text, so they can be opened
/// straight away. Pure logic, so it's unit tested.
enum LinkFinder {
    /// The prompt lists at most this many.
    static let limit = 5
    private static let schemes: Set<String> = ["http", "https", "mailto"]

    /// Links in reading order, without duplicates. Bare domains like "github.com/x" become
    /// http links; anything that isn't a web or email link (files, ftp, apps) is left out.
    static func links(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        var seen = Set<String>()
        var links: [URL] = []
        for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let url = match.url, let scheme = url.scheme?.lowercased(), schemes.contains(scheme) else { continue }
            guard seen.insert(url.absoluteString.lowercased()).inserted else { continue }
            links.append(url)
            if links.count == limit { break }
        }
        return links
    }

    /// How a link reads in the prompt: "github.com/Treposting/marquee" without the scheme or a
    /// trailing slash, and the address alone for email.
    static func displayText(_ url: URL) -> String {
        var text = url.absoluteString
        for prefix in ["mailto:", "https://", "http://"] where text.lowercased().hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
            break
        }
        if text.hasSuffix("/") { text.removeLast() }
        return text
    }
}
