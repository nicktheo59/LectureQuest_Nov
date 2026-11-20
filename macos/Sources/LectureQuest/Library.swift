import Foundation

struct Lecture: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var notes = ""
    var cards: [Flashcard] = []
    let material: MaterialKind?

    init(id: UUID = UUID(), title: String, material: MaterialKind? = nil) {
        self.id = id
        self.title = title
        self.material = material
    }

    func dueCards(at date: Date) -> [Flashcard] {
        cards.filter { $0.review.dueAt.map { $0 <= date } ?? true }
    }
}

enum MaterialKind: String, Codable {
    case pdf, txt

    var name: String { self == .pdf ? "PDF" : "Text" }
}

struct Flashcard: Codable, Identifiable, Equatable {
    var id = UUID()
    var prompt: String
    var answer: String
    var review = ReviewProgress()
}

enum Rating {
    case again, gotIt
}

struct ReviewProgress: Codable, Equatable {
    private(set) var dueAt: Date?
    private(set) var lastReviewed: Date?
    private(set) var reviews = 0
    private(set) var intervalDays = 0

    mutating func record(_ rating: Rating, at now: Date) {
        reviews += 1
        lastReviewed = now
        switch rating {
        case .again:
            intervalDays = 0
            dueAt = now.addingTimeInterval(10 * 60)
        case .gotIt:
            intervalDays = intervalDays < 1 ? 1 : min(intervalDays, 15) * 2
            dueAt = now.addingTimeInterval(TimeInterval(intervalDays) * 86_400)
        }
    }
}

struct LibraryDisk {
    let root: URL
    private let files = FileManager.default

    private struct Manifest: Codable {
        let version: Int
        let lectures: [Lecture]
    }

    private var index: URL { root.appendingPathComponent("library.json") }
    private var materials: URL { root.appendingPathComponent("Materials", isDirectory: true) }

    static func applicationSupport() throws -> LibraryDisk {
        let support = try FileManager.default.url(for: .applicationSupportDirectory,
                                                   in: .userDomainMask, appropriateFor: nil, create: true)
        return LibraryDisk(root: support.appendingPathComponent("LectureQuest", isDirectory: true))
    }

    func load() throws -> [Lecture] {
        let data: Data
        do {
            data = try Data(contentsOf: index)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        }
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        guard manifest.version == 1 else { throw LibraryError.unknownVersion }
        guard Set(manifest.lectures.map(\.id)).count == manifest.lectures.count,
              manifest.lectures.allSatisfy({ Set($0.cards.map(\.id)).count == $0.cards.count }) else {
            throw LibraryError.duplicateIDs
        }
        return manifest.lectures
    }

    func save(_ lectures: [Lecture]) throws {
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(Manifest(version: 1, lectures: lectures)).write(to: index, options: .atomic)
    }

    func materialURL(for lecture: Lecture) -> URL? {
        lecture.material.map {
            materials.appendingPathComponent(lecture.id.uuidString).appendingPathExtension($0.rawValue)
        }
    }

    // Save the file before publishing its index entry. Roll it back if publishing fails.
    func importMaterial(from source: URL, into lectures: [Lecture],
                        validatePDF: (URL) throws -> Void) throws -> [Lecture] {
        let kind: MaterialKind = source.pathExtension.lowercased() == "pdf" ? .pdf : .txt
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize else {
            throw LibraryError.notAFile
        }
        guard size <= (kind == .pdf ? 64 : 2) * 1_048_576 else {
            throw LibraryError.tooLarge(kind)
        }
        let stem = source.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        let lecture = Lecture(title: stem.isEmpty ? "Untitled lecture" : stem, material: kind)
        guard let destination = materialURL(for: lecture) else { throw LibraryError.notAFile }
        try files.createDirectory(at: materials, withIntermediateDirectories: true)
        let next = [lecture] + lectures
        do {
            switch kind {
            case .pdf:
                try files.copyItem(at: source, to: destination)
                try validatePDF(destination)
            case .txt:
                let data = try Data(contentsOf: source)
                let text: String?
                if data.starts(with: [UInt8(0xFF), 0xFE]) || data.starts(with: [UInt8(0xFE), 0xFF]) {
                    text = String(data: data, encoding: .utf16)
                } else {
                    text = String(data: data, encoding: .utf8)
                }
                guard var text, !text.contains("\0") else { throw LibraryError.badText }
                if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
                try Data(text.utf8).write(to: destination, options: .atomic)
            }
            try save(next)
            return next
        } catch {
            try? files.removeItem(at: destination)
            throw error
        }
    }

    func removeMaterial(for lecture: Lecture) throws {
        guard let url = materialURL(for: lecture) else { return }
        do {
            try files.removeItem(at: url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            // Already removed.
        }
    }
}

enum LibraryError: LocalizedError, Equatable {
    case unknownVersion, duplicateIDs, notAFile, tooLarge(MaterialKind), badText, unreadablePDF

    var errorDescription: String? {
        switch self {
        case .unknownVersion: return "This library was created by an unsupported version of LectureQuest."
        case .duplicateIDs: return "The library contains duplicate entries."
        case .notAFile: return "Choose a regular file."
        case .tooLarge(let kind): return "Choose a \(kind.name) file no larger than \(kind == .pdf ? 64 : 2) MiB."
        case .badText: return "Choose a UTF-8 text file or a UTF-16 text file with a byte-order mark."
        case .unreadablePDF: return "This PDF is damaged, password-protected, or has no pages."
        }
    }
}
