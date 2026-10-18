import AppKit
import SwiftUI

/// Who makes Marquee and where to find it, for the About panel and the Home page.
enum AppInfo {
    static let author = "Nahid Hassan Bulbul"
    static let authorRole = "Full Stack Web Developer, Bangladesh"
    static let authorGitHub = URL(string: "https://github.com/0nahid")!
    static let authorWebsite = URL(string: "https://nahid.pages.dev/")!
    static let repository = URL(string: "https://github.com/Treposting/marquee")!
    static let website = URL(string: "https://treposting.github.io/marquee/")!
    /// Marquee is free; this is where people can say thanks.
    static let buyMeACoffee = URL(string: "https://buymeacoffee.com/0nahid")!

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    /// The standard About panel, with the maker and links in its credits.
    @MainActor
    static func showAboutPanel() {
        let body = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let center = NSMutableParagraphStyle()
        center.alignment = .center
        center.paragraphSpacing = 4
        let plain: [NSAttributedString.Key: Any] = [.font: body, .paragraphStyle: center, .foregroundColor: NSColor.labelColor]
        let secondary: [NSAttributedString.Key: Any] = [.font: body, .paragraphStyle: center, .foregroundColor: NSColor.secondaryLabelColor]

        let credits = NSMutableAttributedString(string: "Made by \(author)\n", attributes: plain)
        credits.append(NSAttributedString(string: "\(authorRole)\n", attributes: secondary))
        let links = [("GitHub", authorGitHub), ("Website", authorWebsite), ("Source code", repository)]
        for (title, url) in links {
            var link = plain
            link[.link] = url
            credits.append(NSAttributedString(string: title, attributes: link))
            if url != links.last?.1 { credits.append(NSAttributedString(string: "  ·  ", attributes: secondary)) }
        }
        credits.append(NSAttributedString(string: "\n\nFree and open source under the MIT License.\nEnjoying it? ", attributes: secondary))
        var coffee = plain
        coffee[.link] = buyMeACoffee
        credits.append(NSAttributedString(string: "Buy me a coffee ☕", attributes: coffee))

        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}

/// The line at the bottom of Home: version, maker and links.
struct AboutFooter: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("Marquee \(AppInfo.version)")
            Text("·")
            Text("Made by")
            Link(AppInfo.author, destination: AppInfo.authorGitHub)
                .help("github.com/0nahid")
            Text("·")
            Link("Website", destination: AppInfo.authorWebsite)
            Text("·")
            Link("Source code", destination: AppInfo.repository)
            Spacer(minLength: 8)
            Link(destination: AppInfo.buyMeACoffee) {
                Label("Buy me a coffee", systemImage: "cup.and.saucer.fill")
            }
            .help("Marquee is free. Say thanks at buymeacoffee.com/0nahid")
        }
        .font(.system(size: 11.5))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .contain)
    }
}
