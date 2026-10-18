import XCTest
@testable import Marquee

final class CameraStyleTests: XCTestCase {
    func testBubbleSitsInTheChosenCornerOfTheArea() {
        let area = CGRect(x: 100, y: 50, width: 800, height: 600)
        let size = CGSize(width: 170, height: 170)
        XCTAssertEqual(CameraStyle.frame(in: area, size: size, position: .bottomLeft).origin, CGPoint(x: 124, y: 74))
        XCTAssertEqual(CameraStyle.frame(in: area, size: size, position: .bottomRight).origin, CGPoint(x: 706, y: 74))
        XCTAssertEqual(CameraStyle.frame(in: area, size: size, position: .topLeft).origin, CGPoint(x: 124, y: 456))
        XCTAssertEqual(CameraStyle.frame(in: area, size: size, position: .topRight).origin, CGPoint(x: 706, y: 456))
    }

    func testShapes() {
        XCTAssertEqual(CameraStyle.Shape.circle.cornerRadius(for: CGSize(width: 170, height: 170)), 85)
        XCTAssertEqual(CameraStyle.Shape.portrait.aspect, 0.75)
        XCTAssertEqual(CameraStyle.Shape.square.aspect, 1)
    }

    func testGrowingKeepsTheBubbleInItsCornerAndOnScreen() {
        let area = CGRect(x: 0, y: 0, width: 800, height: 600)
        // Small bubble in the bottom-right corner, 24 pt from the edges.
        let small = CGRect(x: 656, y: 24, width: 120, height: 120)
        let large = CameraStyle.resized(small, to: CGSize(width: 240, height: 240), in: area)
        XCTAssertEqual(large.maxX, 776, "keeps its distance from the right edge")
        XCTAssertEqual(large.minY, 24, "keeps its distance from the bottom edge")
        XCTAssertTrue(area.contains(large))

        // Top-left stays anchored top-left.
        let topLeft = CGRect(x: 24, y: 456, width: 120, height: 120)
        let grown = CameraStyle.resized(topLeft, to: CGSize(width: 180, height: 240), in: area)
        XCTAssertEqual(grown.minX, 24)
        XCTAssertEqual(grown.maxY, 576)
    }

    func testBubbleIsPulledBackInsideTheArea() {
        let area = CGRect(x: 100, y: 100, width: 500, height: 400)
        let outside = CGRect(x: 550, y: 50, width: 120, height: 120)
        XCTAssertEqual(CameraStyle.clamped(outside, in: area), CGRect(x: 480, y: 100, width: 120, height: 120))
        let tooBig = CGRect(x: 0, y: 0, width: 900, height: 900)
        XCTAssertEqual(CameraStyle.clamped(tooBig, in: area).midX, area.midX, "bigger than the area: centered")
    }
}
