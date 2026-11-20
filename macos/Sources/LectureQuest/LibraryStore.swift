import Foundation
import PDFKit
import SwiftUI

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var lectures: [Lecture] = []
    @Published private(set) var loadFailure: String?
    @Published var notice: String?
    @Published private(set) var unsavedNotes: [UUID: String] = [:]

    private var disk: LibraryDisk?

    init() {
        do {
            let disk = try LibraryDisk.applicationSupport()
            lectures = try disk.load()
            self.disk = disk
        } catch {
            loadFailure = error.localizedDescription
        }
    }

    func lecture(_ id: UUID) -> Lecture? { lectures.first { $0.id == id } }
    func materialURL(for lecture: Lecture) -> URL? { disk?.materialURL(for: lecture) }

    func create(title: String) -> UUID? {
        let lecture = Lecture(title: title)
        return persist([lecture] + lectures) ? lecture.id : nil
    }

    func importFile(_ result: Result<[URL], Error>) -> UUID? {
        guard let disk else { return nil }
        do {
            guard let source = try result.get().first else { return nil }
            let accessed = source.startAccessingSecurityScopedResource()
            defer { if accessed { source.stopAccessingSecurityScopedResource() } }
            lectures = try disk.importMaterial(from: source, into: lectures) { url in
                guard let document = PDFDocument(url: url), !document.isLocked, document.pageCount > 0 else {
                    throw LibraryError.unreadablePDF
                }
            }
            notice = nil
            return lectures.first?.id
        } catch let error as CocoaError where error.code == .userCancelled {
            return nil
        } catch {
            notice = "Import failed: \(error.localizedDescription)"
            return nil
        }
    }

    func rename(_ id: UUID, title: String) -> Bool {
        mutate(id) { $0.title = title }
    }

    func delete(_ id: UUID) -> Bool {
        guard let lecture = lecture(id), persist(lectures.filter { $0.id != id }) else { return false }
        unsavedNotes[id] = nil
        do {
            try disk?.removeMaterial(for: lecture)
        } catch {
            notice = "Lecture deleted, but its local material copy could not be removed: \(error.localizedDescription)"
        }
        return true
    }

    func notes(for id: UUID) -> String {
        unsavedNotes[id] ?? lecture(id)?.notes ?? ""
    }

    func saveNotes(_ notes: String, for id: UUID) {
        guard let lecture = lecture(id) else { return }
        if notes == lecture.notes || mutate(id, { $0.notes = notes }) {
            let hadUnsavedNotes = unsavedNotes.removeValue(forKey: id) != nil
            if hadUnsavedNotes && unsavedNotes.isEmpty { notice = nil }
        } else {
            unsavedNotes[id] = notes
        }
    }

    func saveCard(in id: UUID, cardID: UUID?, prompt: String, answer: String) -> Bool {
        if let cardID, lecture(id)?.cards.contains(where: { $0.id == cardID }) != true { return false }
        return mutate(id) { lecture in
            if let cardID {
                guard let index = lecture.cards.firstIndex(where: { $0.id == cardID }) else { return }
                lecture.cards[index].prompt = prompt
                lecture.cards[index].answer = answer
            } else {
                lecture.cards.append(Flashcard(prompt: prompt, answer: answer))
            }
        }
    }

    func deleteCard(_ cardID: UUID, from lectureID: UUID) {
        _ = mutate(lectureID) { $0.cards.removeAll { $0.id == cardID } }
    }

    func rate(_ cardID: UUID, in lectureID: UUID, as rating: Rating, at date: Date = Date()) -> Bool {
        guard lecture(lectureID)?.cards.contains(where: { $0.id == cardID }) == true else { return false }
        return mutate(lectureID) { lecture in
            if let index = lecture.cards.firstIndex(where: { $0.id == cardID }) {
                lecture.cards[index].review.record(rating, at: date)
            }
        }
    }

    private func mutate(_ id: UUID, _ edit: (inout Lecture) -> Void) -> Bool {
        guard let index = lectures.firstIndex(where: { $0.id == id }) else { return false }
        var next = lectures
        edit(&next[index])
        return persist(next)
    }

    private func persist(_ next: [Lecture]) -> Bool {
        guard let disk else { return false }
        do {
            try disk.save(next)
            lectures = next
            notice = nil
            return true
        } catch {
            notice = "Changes could not be saved: \(error.localizedDescription)"
            return false
        }
    }
}
