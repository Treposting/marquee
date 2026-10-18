import XCTest
@testable import Marquee

final class RecordResolutionTests: XCTestCase {
    func testOriginalKeepsRetinaSize() {
        let (w, h) = ScreenRecorder.outputSize(for: CGSize(width: 1440, height: 900), backingScale: 2)
        XCTAssertEqual(w, 2880); XCTAssertEqual(h, 1800)
    }

    func testFitsTheChosenBox() {
        let (w, h) = ScreenRecorder.outputSize(for: CGSize(width: 1440, height: 900), backingScale: 2, resolution: .hd1080)
        XCTAssertEqual(h, 1080); XCTAssertEqual(w, 1728)
        let (w7, h7) = ScreenRecorder.outputSize(for: CGSize(width: 1600, height: 900), backingScale: 2, resolution: .hd720)
        XCTAssertEqual(w7, 1280); XCTAssertEqual(h7, 720)
    }

    func testPortraitAreasUseTheBoxOnItsSide() {
        let (w, h) = ScreenRecorder.outputSize(for: CGSize(width: 500, height: 1000), backingScale: 2, resolution: .hd1080)
        XCTAssertEqual(h, 1920); XCTAssertEqual(w, 960)
    }

    func testNeverScalesUpSmallAreas() {
        let (w, h) = ScreenRecorder.outputSize(for: CGSize(width: 300, height: 200), backingScale: 1, resolution: .hd1080)
        XCTAssertEqual(w, 300); XCTAssertEqual(h, 200)
    }
}
