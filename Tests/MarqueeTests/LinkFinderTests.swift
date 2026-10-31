import XCTest
@testable import Marquee

final class LinkFinderTests: XCTestCase {
    func testFindsWebAndEmailLinksInOrder() {
        let text = """
        Release notes: https://github.com/Treposting/marquee/releases
        Questions? hello@marquee.app or see treposting.github.io/marquee
        """
        let links = LinkFinder.links(in: text).map(\.absoluteString)
        XCTAssertEqual(links.count, 3)
        XCTAssertEqual(links[0], "https://github.com/Treposting/marquee/releases")
        XCTAssertEqual(links[1], "mailto:hello@marquee.app")
        XCTAssertTrue(links[2].hasSuffix("treposting.github.io/marquee"))
    }

    func testSkipsDuplicatesAndOtherSchemes() {
        let text = "https://example.com https://EXAMPLE.com ftp://files.example.com/a.zip"
        XCTAssertEqual(LinkFinder.links(in: text).map(\.absoluteString), ["https://example.com"])
    }

    func testNoLinks() {
        XCTAssertTrue(LinkFinder.links(in: "Just a sentence, with no address in it.").isEmpty)
        XCTAssertTrue(LinkFinder.links(in: "").isEmpty)
    }

    func testAtMostFive() {
        let text = (1...8).map { "https://site\($0).example.com" }.joined(separator: " ")
        XCTAssertEqual(LinkFinder.links(in: text).count, LinkFinder.limit)
    }

    func testDisplayText() {
        XCTAssertEqual(LinkFinder.displayText(URL(string: "https://github.com/Treposting/marquee/")!), "github.com/Treposting/marquee")
        XCTAssertEqual(LinkFinder.displayText(URL(string: "mailto:hello@marquee.app")!), "hello@marquee.app")
        XCTAssertEqual(LinkFinder.displayText(URL(string: "http://example.com/a?b=1")!), "example.com/a?b=1")
    }
}
