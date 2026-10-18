import XCTest
@testable import Marquee

final class VoiceFolderTests: XCTestCase {
    func testVideoAndVoiceShareAFolderAndName() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("voice-folder-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let date = Date(timeIntervalSince1970: 1_800_000_000)

        func makeFiles() throws -> (URL, URL) {
            let video = root.appendingPathComponent("tmp-\(UUID().uuidString).mp4")
            let voice = root.appendingPathComponent("tmp-\(UUID().uuidString).m4a")
            try Data("video".utf8).write(to: video)
            try Data("voice".utf8).write(to: voice)
            return (video, voice)
        }

        let (video, voice) = try makeFiles()
        let folder = try ScreenRecorder.makeVoiceFolder(in: root, date: date, video: video, voice: voice)
        let name = folder.lastPathComponent
        XCTAssertTrue(name.hasPrefix("Marquee Recording "))
        let contents = try fm.contentsOfDirectory(atPath: folder.path).sorted()
        XCTAssertEqual(contents, ["\(name) Voice.m4a", "\(name).mp4"])
        XCTAssertTrue(fm.fileExists(atPath: video.path), "the video is copied; Marquee still uses it")
        XCTAssertFalse(fm.fileExists(atPath: voice.path), "the voice is moved")

        // A second recording in the same second gets its own folder.
        let (video2, voice2) = try makeFiles()
        let second = try ScreenRecorder.makeVoiceFolder(in: root, date: date, video: video2, voice: voice2)
        XCTAssertEqual(second.lastPathComponent, "\(name) (2)")
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: second.path).count, 2)
    }
}
