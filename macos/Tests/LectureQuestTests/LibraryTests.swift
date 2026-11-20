import Foundation
import XCTest
@testable import LectureQuest

final class LibraryTests: XCTestCase {
    func testLocalRoundTripPreservesNotesAndReview() throws {
        let disk = try temporaryDisk()
        XCTAssertEqual(try disk.load(), [])
        var lecture = Lecture(title: "Vectors")
        lecture.notes = "Dot products → projections"
        lecture.cards = [Flashcard(prompt: "What is a unit vector?", answer: "A vector of length 1.")]
        lecture.cards[0].review.record(.gotIt, at: Date(timeIntervalSince1970: 50))
        try disk.save([lecture])
        XCTAssertEqual(try disk.load(), [lecture])
    }

    func testTextImportOwnsCopyAndRemovesOnlyCopy() throws {
        let disk = try temporaryDisk()
        let source = disk.root.deletingLastPathComponent().appendingPathComponent("Week 01.TXT")
        try Data([0xFF, 0xFE] + Array("Vector notes".data(using: .utf16LittleEndian)!)).write(to: source)
        let existing = Lecture(title: "Older lecture")
        let result = try disk.importMaterial(from: source, into: [existing]) { _ in
            XCTFail("Text should not go through the PDF validator")
        }
        let imported = try XCTUnwrap(result.first)
        XCTAssertEqual(imported.title, "Week 01")
        XCTAssertEqual(imported.material, .txt)
        XCTAssertEqual(result.last, existing)
        // Import persists its own copy, not a link back to the original.
        try Data("Replaced original".utf8).write(to: source)
        let copy = try XCTUnwrap(disk.materialURL(for: imported))
        XCTAssertEqual(try String(contentsOf: copy, encoding: .utf8), "Vector notes")
        XCTAssertEqual(try disk.load(), result)
        try disk.save([existing])
        try disk.removeMaterial(for: imported)
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try disk.load(), [existing])
    }

    func testRejectedPDFLeavesExistingLibraryAndNoCopy() throws {
        let disk = try temporaryDisk()
        let existing = Lecture(title: "Keep me")
        try disk.save([existing])
        let source = disk.root.deletingLastPathComponent().appendingPathComponent("Bad.pdf")
        try Data("Bad PDF".utf8).write(to: source)
        XCTAssertThrowsError(try disk.importMaterial(from: source, into: [existing]) { url in
            XCTAssertNotEqual(url, source)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            throw LibraryError.unreadablePDF
        })
        XCTAssertEqual(try disk.load(), [existing])
        let materials = disk.root.appendingPathComponent("Materials", isDirectory: true)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: materials.path), [])
    }

    func testMalformedOrUnknownManifestIsNotTreatedAsEmpty() throws {
        let disk = try temporaryDisk()
        try FileManager.default.createDirectory(at: disk.root, withIntermediateDirectories: true)
        let index = disk.root.appendingPathComponent("library.json")
        let malformed = Data("{not json".utf8)
        try malformed.write(to: index)
        XCTAssertThrowsError(try disk.load())
        XCTAssertEqual(try Data(contentsOf: index), malformed)
        try Data(#"{"version":2,"lectures":[]}"#.utf8).write(to: index)
        XCTAssertThrowsError(try disk.load()) { error in
            XCTAssertEqual(error as? LibraryError, .unknownVersion)
        }
    }

    func testDueCardsAndIntervals() {
        let date = Date(timeIntervalSince1970: 0)
        var lecture = Lecture(title: "Review")
        lecture.cards = [Flashcard(prompt: "A", answer: "B")]
        XCTAssertEqual(lecture.dueCards(at: date).count, 1)
        for days in [1, 2, 4, 8, 16, 30, 30] {
            lecture.cards[0].review.record(.gotIt, at: date)
            XCTAssertEqual(lecture.cards[0].review.intervalDays, days)
            XCTAssertEqual(lecture.cards[0].review.dueAt, date.addingTimeInterval(Double(days) * 86_400))
        }
        lecture.cards[0].review.record(.again, at: date)
        XCTAssertEqual(lecture.cards[0].review.intervalDays, 0)
        XCTAssertEqual(lecture.cards[0].review.lastReviewed, date)
        XCTAssertEqual(lecture.cards[0].review.reviews, 8)
        XCTAssertTrue(lecture.dueCards(at: date.addingTimeInterval(599)).isEmpty)
        XCTAssertEqual(lecture.dueCards(at: date.addingTimeInterval(600)).count, 1)
        lecture.cards[0].review.record(.gotIt, at: date)
        XCTAssertEqual(lecture.cards[0].review.intervalDays, 1)
    }

    private func temporaryDisk() throws -> LibraryDisk {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return LibraryDisk(root: directory.appendingPathComponent("Library", isDirectory: true))
    }
}
