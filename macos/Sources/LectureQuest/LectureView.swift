import AppKit
import PDFKit
import SwiftUI

@MainActor
struct LectureView: View {
    enum Section: String, CaseIterable { case material = "Material", notes = "Notes", cards = "Flashcards" }

    let lecture: Lecture
    @ObservedObject var store: LibraryStore
    @State private var section: Section = .notes

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Label(lecture.material.map { "\($0.name) LECTURE" } ?? "LECTURE NOTEBOOK", systemImage: "book.closed")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(lecture.title).font(.largeTitle.bold()).lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                Picker("Lecture section", selection: $section) {
                    ForEach(Section.allCases, id: \.self) { item in Text(item.rawValue).tag(item) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 420)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
            Divider()
            switch section {
            case .material:
                if let kind = lecture.material, let url = store.materialURL(for: lecture) {
                    MaterialReader(kind: kind, url: url)
                } else {
                    ContentUnavailableView("No attached material", systemImage: "doc.badge.plus",
                                           description: Text("Import Material creates a separate lecture with its own notes and deck."))
                }
            case .notes:
                VStack(alignment: .leading, spacing: 0) {
                    TextEditor(text: Binding(get: { store.notes(for: lecture.id) },
                                             set: { store.saveNotes($0, for: lecture.id) }))
                        .font(.body)
                        .accessibilityLabel("Lecture notes")
                        .padding(.horizontal, 19)
                        .padding(.vertical, 12)
                    Divider()
                    HStack {
                        if let draft = store.unsavedNotes[lecture.id] {
                            Label("Not saved. Keep LectureQuest open until the retry succeeds.", systemImage: "exclamationmark.circle")
                            Spacer()
                            Button("Retry Save") { store.saveNotes(draft, for: lecture.id) }
                        } else {
                            Label("Notes save automatically on this Mac", systemImage: "checkmark.circle")
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 22).padding(.vertical, 10)
                }
            case .cards:
                DeckView(lecture: lecture, store: store)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { if lecture.material != nil { section = .material } }
    }
}

@MainActor
private struct MaterialReader: View {
    let kind: MaterialKind
    let url: URL
    @State private var document: PDFDocument?
    @State private var text: String?
    @State private var failure: String?

    var body: some View {
        Group {
            if let document {
                PDFSurface(document: document)
            } else if let text {
                TextSurface(text: text)
            } else if let failure {
                ContentUnavailableView("Material couldn’t be opened", systemImage: "doc.badge.ellipsis",
                                       description: Text(failure))
            } else {
                ProgressView("Opening material…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: url) {
            document = nil
            text = nil
            failure = nil
            if kind == .pdf {
                if let pdf = PDFDocument(url: url), !pdf.isLocked, pdf.pageCount > 0 {
                    document = pdf
                } else {
                    failure = "The local PDF copy is missing or unreadable. You can import the original again as a new lecture."
                }
            } else {
                do { text = try String(contentsOf: url, encoding: .utf8) }
                catch { failure = "The local text copy is missing or unreadable. You can import the original again as a new lecture." }
            }
        }
    }
}

private struct PDFSurface: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = document
        view.autoScales = true
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document !== document {
            view.document = document
            view.autoScales = true
        }
    }
}

private struct TextSurface: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let view = scrollView.documentView as? NSTextView
        view?.isEditable = false
        view?.isRichText = false
        view?.isSelectable = true
        view?.usesFindBar = true
        view?.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        view?.textContainerInset = NSSize(width: 22, height: 16)
        view?.setAccessibilityLabel("Lecture material")
        view?.string = text
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        if let view = scrollView.documentView as? NSTextView, view.string != text { view.string = text }
    }
}
