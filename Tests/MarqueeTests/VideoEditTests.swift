import XCTest
@testable import Marquee

final class VideoEditTests: XCTestCase {
    func testWholeVideoByDefault() {
        let edit = VideoEdit(duration: 30)
        XCTAssertEqual(edit.keptSegments, [0...30])
        XCTAssertEqual(edit.keptDuration, 30)
        XCTAssertTrue(edit.isEmpty)
    }

    func testCutsSplitTheVideo() {
        var edit = VideoEdit(duration: 30)
        edit.remove(from: 10, to: 12)
        edit.remove(from: 20, to: 25)
        XCTAssertEqual(edit.keptSegments, [0...10, 12...20, 25...30])
        XCTAssertEqual(edit.keptDuration, 23)
    }

    func testOverlappingCutsMerge() {
        var edit = VideoEdit(duration: 30)
        edit.remove(from: 10, to: 15)
        edit.remove(from: 14, to: 18)
        edit.remove(from: 12, to: 11) // reversed marks still work
        XCTAssertEqual(edit.removed, [10...18])
        edit.restore(10...18)
        XCTAssertEqual(edit.keptSegments, [0...30])
    }

    func testTrimAndCutsTogether() {
        var edit = VideoEdit(duration: 30)
        edit.trim = 5...25
        edit.remove(from: 0, to: 7)      // partly before the trim
        edit.remove(from: 24, to: 29)    // partly after it
        XCTAssertEqual(edit.keptSegments, [7...24])
    }

    func testTimesShiftAroundCuts() {
        var edit = VideoEdit(duration: 30)
        edit.remove(from: 10, to: 12)
        XCTAssertEqual(edit.editedTime(for: 5), 5)
        XCTAssertEqual(edit.editedTime(for: 11), 10, "inside a cut lands where the cut was")
        XCTAssertEqual(edit.editedTime(for: 15), 13)
        edit.trim = 2...30
        XCTAssertEqual(edit.editedTime(for: 3), 1)
        XCTAssertEqual(edit.cut(containing: 11), 10...12)
        XCTAssertNil(edit.cut(containing: 12))
    }

    func testTinyPiecesAreDropped() {
        var edit = VideoEdit(duration: 10)
        edit.remove(from: 0, to: 9.98)
        XCTAssertEqual(edit.keptSegments, [], "a 0.02 s leftover isn't worth a frame")
        edit.remove(from: 5, to: 5.01)
        XCTAssertEqual(edit.removed.count, 1, "too short to be a cut")
    }

    func testTextVisibility() {
        let whole = TextOverlay(text: "Hi")
        XCTAssertTrue(whole.isVisible(at: 99))
        let timed = TextOverlay(text: "Hi", start: 2, end: 5)
        XCTAssertFalse(timed.isVisible(at: 1.9))
        XCTAssertTrue(timed.isVisible(at: 2))
        XCTAssertFalse(timed.isVisible(at: 5))
    }
}
