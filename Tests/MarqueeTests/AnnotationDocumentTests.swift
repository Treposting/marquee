import AppKit
import XCTest
@testable import Marquee

@MainActor
final class AnnotationDocumentTests: XCTestCase {
    private func document() -> AnnotationDocument {
        let image = NSImage(size: NSSize(width: 400, height: 300), flipped: false) { r in
            NSColor.systemTeal.setFill(); r.fill(); return true
        }
        return AnnotationDocument(image: image)
    }

    private func drag(_ doc: AnnotationDocument, _ from: CGPoint, _ to: CGPoint) {
        doc.dragChanged(from: from, to: to)
        doc.dragEnded(at: to)
    }

    func testRedactionStaysMovableAndResizable() {
        let doc = document()
        doc.tool = .pixelate
        doc.redactStyle = .blur
        drag(doc, CGPoint(x: 50, y: 50), CGPoint(x: 150, y: 100))
        XCTAssertEqual(doc.annotations.count, 1)
        XCTAssertEqual(doc.annotations[0].redact, .blur)
        XCTAssertEqual(doc.selectedID, doc.annotations[0].id, "a new redaction is selected")

        // Dragging inside it moves it instead of drawing another.
        drag(doc, CGPoint(x: 100, y: 75), CGPoint(x: 130, y: 95))
        XCTAssertEqual(doc.annotations.count, 1)
        XCTAssertEqual(doc.annotations[0].rect, CGRect(x: 80, y: 70, width: 100, height: 50))

        // Dragging its bottom-right corner resizes it; the top-left stays.
        drag(doc, CGPoint(x: 180, y: 120), CGPoint(x: 230, y: 160))
        XCTAssertEqual(doc.annotations[0].rect, CGRect(x: 80, y: 70, width: 150, height: 90))

        // Changing the style restyles the selected redaction.
        doc.redactStyle = .solid
        XCTAssertEqual(doc.annotations[0].redact, .solid)

        // Undo steps back through restyle, resize and move.
        doc.undo()
        XCTAssertEqual(doc.annotations[0].redact, .blur)
        doc.undo()
        XCTAssertEqual(doc.annotations[0].rect, CGRect(x: 80, y: 70, width: 100, height: 50))
        doc.undo()
        XCTAssertEqual(doc.annotations[0].rect, CGRect(x: 50, y: 50, width: 100, height: 50))
        doc.redo()
        XCTAssertEqual(doc.annotations[0].rect, CGRect(x: 80, y: 70, width: 100, height: 50))
    }

    func testSelectToolMovesAnyShapeAndDeletes() {
        let doc = document()
        doc.tool = .arrow
        drag(doc, CGPoint(x: 20, y: 20), CGPoint(x: 120, y: 60))
        doc.tool = .select
        drag(doc, CGPoint(x: 70, y: 40), CGPoint(x: 90, y: 50))
        XCTAssertEqual(doc.annotations[0].points.first, CGPoint(x: 40, y: 30))
        XCTAssertNotNil(doc.selectedID)
        doc.deleteSelected()
        XCTAssertTrue(doc.annotations.isEmpty)
        doc.undo()
        XCTAssertEqual(doc.annotations.count, 1)
    }

    func testClickingEmptySpaceWithSelectDoesNothing() {
        let doc = document()
        doc.tool = .select
        drag(doc, CGPoint(x: 300, y: 250), CGPoint(x: 320, y: 260))
        XCTAssertTrue(doc.annotations.isEmpty)
        XCTAssertNil(doc.selectedID)
        XCTAssertFalse(doc.canUndo)
    }
}
