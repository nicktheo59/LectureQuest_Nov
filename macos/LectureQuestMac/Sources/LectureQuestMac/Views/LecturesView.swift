import SwiftUI

struct LecturesView: View {
    @Environment(AppStore.self) private var store
    var startQuiz: (QuizSession) -> Void
    var goTo: (AppSection) -> Void
    @State private var search = ""
    @State private var selected: UUID?

    var body: some View {
        let items = store.lectures.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }
        HSplitView {
            List(selection: $selected) {
                ForEach(items) { l in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(l.title).font(.headline).lineLimit(1)
                        HStack(spacing: 8) {
                            Text(l.date, style: .date)
                            if l.lastReviewed != nil { Text("· \(l.reviewScore)%") }
                            if l.questions.isEmpty { Text("· no quiz yet") }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                    .tag(l.id)
                }
            }
            .searchable(text: $search, placement: .sidebar)
            .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)
            .overlay {
                if store.lectures.isEmpty {
                    ContentUnavailableView {
                        Label("No lectures yet", systemImage: "books.vertical")
                    } actions: {
                        Button("Add Lectures") { goTo(.importer) }
                    }
                }
            }

            Group {
                if let id = selected ?? items.first?.id, let l = store.lecture(id) {
                    LectureDetail(lecture: l, startQuiz: startQuiz)
                        .id(l.id)
                } else {
                    Text("Select a lecture").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct LectureRow: View {
    var lecture: Lecture
    var startQuiz: (QuizSession) -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(lecture.title).font(.headline)
                Text(lecture.lastReviewed == nil ? "Not reviewed yet" : "Last score \(lecture.reviewScore)%")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            QuizButton(lecture: lecture, startQuiz: startQuiz)
        }
    }
}

/// Starts a lecture quiz, generating it with Claude first if needed.
struct QuizButton: View {
    @Environment(AppStore.self) private var store
    var lecture: Lecture
    var startQuiz: (QuizSession) -> Void
    var regenerate = false
    @State private var busy = false

    var body: some View {
        Button {
            Task {
                busy = true
                defer { busy = false }
                do {
                    if regenerate || lecture.questions.isEmpty { try await store.generateQuiz(for: lecture.id) }
                    if !regenerate, let s = store.startLectureQuiz(lecture.id) { startQuiz(s) }
                } catch {
                    store.lastError = error.localizedDescription
                }
            }
        } label: {
            if busy {
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Generating…") }
            } else if regenerate {
                Label("New questions", systemImage: "arrow.clockwise")
            } else {
                Text(lecture.questions.isEmpty ? "Generate Quiz" : "Take Quiz")
            }
        }
        .disabled(busy || !store.hasAPIKey && lecture.questions.isEmpty)
        .buttonStyle(.bordered)
    }
}

struct LectureDetail: View {
    @Environment(AppStore.self) private var store
    var lecture: Lecture
    var startQuiz: (QuizSession) -> Void
    @State private var renaming = false
    @State private var newTitle = ""
    @State private var confirmDelete = false

    var body: some View {
        let topics = store.topicStats.filter { $0.lectureID == lecture.id }.sorted { $0.lastScore < $1.lastScore }
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    PageHeader(title: lecture.title,
                               subtitle: "\(lecture.wordCount.formatted()) words · added \(lecture.date.formatted(date: .abbreviated, time: .omitted))")
                    Menu {
                        Button("Rename…") { newTitle = lecture.title; renaming = true }
                        Button("Delete…", role: .destructive) { confirmDelete = true }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).fixedSize()
                }

                HStack(spacing: 12) {
                    StatPill(symbol: "target", value: lecture.lastReviewed == nil ? "—" : "\(lecture.reviewScore)%", label: "Last score")
                    StatPill(symbol: "rosette", value: "\(lecture.bestScore)%", label: "Best", tint: Theme.gold)
                    StatPill(symbol: "bolt.fill", value: "\(lecture.xpEarned)", label: "XP earned", tint: Theme.gold)
                    StatPill(symbol: "repeat", value: "\(lecture.attempts.count)", label: "Attempts")
                }

                HStack {
                    QuizButton(lecture: lecture, startQuiz: startQuiz).buttonStyle(.borderedProminent)
                    if !lecture.questions.isEmpty {
                        QuizButton(lecture: lecture, startQuiz: startQuiz, regenerate: true)
                    }
                }

                if !topics.isEmpty {
                    Card {
                        Text("Topics").font(Theme.serif(20))
                        ForEach(topics) { t in
                            HStack {
                                Text(t.topic)
                                Spacer()
                                if t.isMastered { Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.success).help("Mastered") }
                                Text("\(t.lastScore)%").monospacedDigit().foregroundStyle(t.lastScore >= 70 ? Theme.success : .orange)
                                Text("next: \(t.nextDue.formatted(.relative(presentation: .named)))")
                                    .font(.caption).foregroundStyle(.secondary).frame(width: 120, alignment: .trailing)
                            }
                        }
                    }
                }

                if !lecture.skills.isEmpty {
                    Card {
                        Text("Transferable skills").font(Theme.serif(20))
                        ForEach(lecture.skills) { s in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(s.name).font(.headline)
                                    Text(s.proficiency.rawValue.capitalized).font(.caption).foregroundStyle(s.proficiency.color)
                                }
                                Text(s.description).font(.callout).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Card {
                    Text("Content").font(Theme.serif(20))
                    Text(String(lecture.content.prefix(4000)) + (lecture.content.count > 4000 ? "…" : ""))
                        .font(.callout).textSelection(.enabled).foregroundStyle(.secondary)
                }
            }
            .padding(28)
        }
        .alert("Rename lecture", isPresented: $renaming) {
            TextField("Title", text: $newTitle)
            Button("Save") { store.rename(lecture.id, to: newTitle) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete “\(lecture.title)”?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { store.delete(lecture.id) }
        } message: {
            Text("This removes the lecture and its spaced-repetition history.")
        }
    }
}
