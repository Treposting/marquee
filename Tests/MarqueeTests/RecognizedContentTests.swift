import XCTest
@testable import Marquee

final class RecognizedContentTests: XCTestCase {
    func testCodesComeFirstAndAppearOnce() {
        let content = RecognizedContent(text: "Scan to join\nhttps://marquee.app/join", codes: ["https://marquee.app/join", "https://marquee.app/join"])
        XCTAssertEqual(content.clipboardText, "https://marquee.app/join\n\nScan to join\nhttps://marquee.app/join")
        XCTAssertEqual(content.links.map(\.absoluteString), ["https://marquee.app/join"])
    }

    func testQRCodeOnly() {
        let content = RecognizedContent(text: "", codes: ["mailto:hello@marquee.app"])
        XCTAssertEqual(content.clipboardText, "mailto:hello@marquee.app")
        XCTAssertEqual(content.summary, "Copied QR code")
        XCTAssertEqual(content.links.map(\.absoluteString), ["mailto:hello@marquee.app"])
    }

    func testSummaries() {
        XCTAssertEqual(RecognizedContent(text: "Hello", codes: []).summary, "Copied text (5 characters)")
        XCTAssertEqual(RecognizedContent(text: "Hello", codes: ["a", "b"]).summary, "Copied text and 2 codes")
        XCTAssertEqual(RecognizedContent(text: "", codes: []).summary, "No text or QR code found")
        XCTAssertTrue(RecognizedContent(text: "", codes: []).isEmpty)
    }

    func testPlainCodeHasNoLinks() {
        let content = RecognizedContent(text: "", codes: ["WIFI:S:Home;T:WPA;P:secret;;"])
        XCTAssertTrue(content.links.isEmpty)
        XCTAssertEqual(content.clipboardText, "WIFI:S:Home;T:WPA;P:secret;;")
    }
}
