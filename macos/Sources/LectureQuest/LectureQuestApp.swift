import AppKit
import SwiftUI
import UniformTypeIdentifiers

// SwiftPM launches a bare executable, rather than an installed .app bundle.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
@MainActor
struct LectureQuestApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = LibraryStore()

    var body: some Scene {
        Window("LectureQuest", id: "library") {
            LibraryView(store: store)
                .frame(minWidth: 720, minHeight: 490)
        }
        .defaultSize(width: 1020, height: 690)
    }
}

@MainActor
struct LibraryView: View {
    @ObservedObject var store: LibraryStore
    @State private var selection: UUID?
    @State private var importing = false
    @State private var titleRequest: TitleRequest?
    @State private var askingToDelete = false

    private var selected: Lecture? { selection.flatMap { store.lecture($0) } }

    var body: some View {
        if let error = store.loadFailure {
            ContentUnavailableView {
                Label("Library couldn’t be opened", systemImage: "externaldrive.badge.exclamationmark")
            } description: {
                Text("\(error)\n\nNo data was overwritten. Check ~/Library/Application Support/LectureQuest, then relaunch.")
            }
        } else {
            VStack(spacing: 0) {
                if let notice = store.notice {
                    HStack(alignment: .top) {
                        Label(notice, systemImage: "exclamationmark.triangle.fill")
                        Spacer()
                        Button { store.notice = nil } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Dismiss message")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.orange.opacity(0.15))
                }
                if !store.unsavedNotes.isEmpty {
                    Label("Unsaved notes remain in memory. Open the marked lecture to retry before quitting.",
                          systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(Color.orange.opacity(0.10))
                }
                NavigationSplitView {
                    List(store.lectures, selection: $selection) { lecture in
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 5) {
                                    Text(lecture.title).lineLimit(1)
                                    if store.unsavedNotes[lecture.id] != nil {
                                        Image(systemName: "exclamationmark.circle")
                                            .foregroundStyle(Color.orange)
                                            .accessibilityLabel("Unsaved notes")
                                    }
                                }
                                Text("\(lecture.cards.count) \(lecture.cards.count == 1 ? "card" : "cards")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        } icon: {
                            Image(systemName: lecture.material == .pdf ? "doc.richtext" : "doc.text")
                        }
                        .tag(lecture.id)
                    }
                    .navigationSplitViewColumnWidth(min: 195, ideal: 245, max: 325)
                    .safeAreaInset(edge: .bottom) {
                        Label("Offline library", systemImage: "internaldrive")
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                } detail: {
                    if let lecture = selected {
                        LectureView(lecture: lecture, store: store).id(lecture.id)
                    } else {
                        ContentUnavailableView {
                            Label(store.lectures.isEmpty ? "Your lecture library" : "Select a lecture",
                                  systemImage: "books.vertical")
                        } description: {
                            Text(store.lectures.isEmpty
                                 ? "Import a PDF or text file, or start with a blank lecture."
                                 : "Choose a lecture to read its material, edit notes, or practice flashcards.")
                        } actions: {
                            if store.lectures.isEmpty {
                                Button("Import Material…") { importing = true }.buttonStyle(.borderedProminent)
                                Button("New Blank Lecture…") { titleRequest = TitleRequest() }
                            }
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItemGroup {
                    Button { titleRequest = TitleRequest() } label: { Label("New Lecture", systemImage: "plus") }
                        .keyboardShortcut("n", modifiers: .command)
                    Button { importing = true } label: { Label("Import Material", systemImage: "square.and.arrow.down") }
                        .keyboardShortcut("o", modifiers: .command)
                    Menu {
                        Button("Rename…") {
                            if let lecture = selected { titleRequest = TitleRequest(lecture: lecture) }
                        }
                        Button("Delete Lecture…", role: .destructive) { askingToDelete = true }
                    } label: { Label("Lecture Actions", systemImage: "ellipsis.circle") }
                    .disabled(selected == nil)
                }
            }
            .fileImporter(isPresented: $importing,
                          allowedContentTypes: [.pdf, .plainText] + [UTType(filenameExtension: "md")].compactMap { $0 },
                          allowsMultipleSelection: false) { result in
                if let id = store.importFile(result) { selection = id }
            }
            .sheet(item: $titleRequest) { request in
                TitleEditor(original: request.lecture?.title ?? "", isNew: request.lecture == nil) { title in
                    if let lecture = request.lecture { return store.rename(lecture.id, title: title) }
                    guard let id = store.create(title: title) else { return false }
                    selection = id
                    return true
                }
            }
            .confirmationDialog("Delete this lecture?", isPresented: $askingToDelete, titleVisibility: .visible,
                                presenting: selected) { lecture in
                Button("Delete Lecture", role: .destructive) {
                    if store.delete(lecture.id) { selection = store.lectures.first?.id }
                }
            } message: { lecture in
                Text("\(lecture.title), its material copy, notes, and flashcards will be removed from this library. The original file is not affected.")
            }
            .onAppear { if selection == nil { selection = store.lectures.first?.id } }
        }
    }
}

private struct TitleRequest: Identifiable {
    let id = UUID()
    var lecture: Lecture?
}

private struct TitleEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var failed = false
    @FocusState private var focused: Bool
    let isNew: Bool
    let save: (String) -> Bool

    init(original: String, isNew: Bool, save: @escaping (String) -> Bool) {
        _title = State(initialValue: original)
        self.isNew = isNew
        self.save = save
    }

    private var cleanTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? "New Lecture" : "Rename Lecture").font(.title2.bold())
            TextField("Lecture title", text: $title).focused($focused)
            if failed { Text("Couldn’t save the title. Check available storage and try again.").foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isNew ? "Create" : "Save") {
                    if save(cleanTitle) { dismiss() } else { failed = true }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(cleanTitle.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 410)
        .onAppear { focused = true }
    }
}
