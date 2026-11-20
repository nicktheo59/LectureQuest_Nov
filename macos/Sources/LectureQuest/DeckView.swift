import SwiftUI

@MainActor
struct DeckView: View {
    let lecture: Lecture
    @ObservedObject var store: LibraryStore
    @State private var editing: CardRequest?
    @State private var deleting: Flashcard?
    @State private var confirmingDelete = false
    @State private var practice: PracticeQueue?

    var body: some View {
        VStack(spacing: 0) {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let due = lecture.dueCards(at: context.date)
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Deck").font(.headline).accessibilityAddTraits(.isHeader)
                        Text("\(lecture.cards.count) total • \(due.count) due")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Add Card…") { editing = CardRequest() }
                    Menu("Practice") {
                        Button("Due Cards (\(due.count))") { startPractice(dueOnly: true) }
                            .disabled(due.isEmpty)
                        Button("All Cards (\(lecture.cards.count))") { startPractice(dueOnly: false) }
                    }
                    .fixedSize()
                    .disabled(lecture.cards.isEmpty)
                }
                .padding(.horizontal, 22).padding(.vertical, 13)
            }
            Divider()
            if lecture.cards.isEmpty {
                ContentUnavailableView("No flashcards yet", systemImage: "rectangle.on.rectangle",
                                       description: Text("Add questions and answers you want to review later."))
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(lecture.cards) { card in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(card.prompt).font(.headline).lineLimit(2)
                                    Text(card.answer).foregroundStyle(.secondary).lineLimit(2)
                                    if let dueAt = card.review.dueAt {
                                        Text("Reviewed \(card.review.reviews)× • Next: \(dueAt.formatted(date: .abbreviated, time: .shortened))")
                                            .font(.caption).foregroundStyle(.secondary)
                                    } else {
                                        Text("New • Ready to practice").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 14)
                                Menu {
                                    Button("Edit…") { editing = CardRequest(card: card) }
                                    Button("Delete…", role: .destructive) {
                                        deleting = card
                                        confirmingDelete = true
                                    }
                                } label: { Image(systemName: "ellipsis.circle").accessibilityLabel("Card actions") }
                                .menuStyle(.borderlessButton)
                                .fixedSize()
                            }
                            .padding(14)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                        }
                    }
                    .padding(.horizontal, 22).padding(.vertical, 15)
                }
            }
        }
        .sheet(item: $editing) { request in
            CardEditor(card: request.card) { prompt, answer in
                store.saveCard(in: lecture.id, cardID: request.card?.id, prompt: prompt, answer: answer)
            }
        }
        .sheet(item: $practice) { queue in
            PracticeView(queue: queue) { card, rating in
                store.rate(card, in: lecture.id, as: rating)
            }
        }
        .confirmationDialog("Delete this flashcard?", isPresented: $confirmingDelete, titleVisibility: .visible,
                            presenting: deleting) { card in
            Button("Delete Flashcard", role: .destructive) { store.deleteCard(card.id, from: lecture.id) }
        } message: { _ in
            Text("The flashcard and its review progress will be removed.")
        }
    }

    private func startPractice(dueOnly: Bool) {
        guard let latest = store.lecture(lecture.id) else { return }
        let cards = dueOnly ? latest.dueCards(at: Date()) : latest.cards
        guard !cards.isEmpty else { return }
        practice = PracticeQueue(cards: cards, dueOnly: dueOnly)
    }
}

private struct CardRequest: Identifiable {
    let id = UUID()
    var card: Flashcard?
}

private struct CardEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var prompt: String
    @State private var answer: String
    @State private var failed = false
    @FocusState private var questionFocused: Bool
    private let isNew: Bool
    let save: (String, String) -> Bool

    init(card: Flashcard?, save: @escaping (String, String) -> Bool) {
        _prompt = State(initialValue: card?.prompt ?? "")
        _answer = State(initialValue: card?.answer ?? "")
        isNew = card == nil
        self.save = save
    }

    private var cleanPrompt: String { prompt.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var cleanAnswer: String { answer.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(isNew ? "Add Flashcard" : "Edit Flashcard").font(.title2.bold())
            field("Question", binding: $prompt).focused($questionFocused)
            field("Answer", binding: $answer)
            if failed { Text("Couldn’t save this card. Check available storage and try again.").foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isNew ? "Add Card" : "Save") {
                    if save(cleanPrompt, cleanAnswer) { dismiss() } else { failed = true }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(cleanPrompt.isEmpty || cleanAnswer.isEmpty)
            }
        }
        .padding(22).frame(width: 510)
        .onAppear { questionFocused = true }
    }

    private func field(_ label: String, binding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.headline)
            TextEditor(text: binding)
                .frame(height: 75)
                .padding(4)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                .accessibilityLabel(label)
        }
    }
}

private struct PracticeQueue: Identifiable {
    let id = UUID()
    let cards: [Flashcard]
    let dueOnly: Bool
}

private struct PracticeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var revealed = false
    @State private var gotIt = 0
    @State private var failed = false
    let queue: PracticeQueue
    let rate: (UUID, Rating) -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text(queue.dueOnly ? "Due Cards" : "Practice All Cards").font(.title2.bold())
                Spacer()
                Text("\(index) / \(queue.cards.count) reviewed").foregroundStyle(.secondary).monospacedDigit()
            }
            ProgressView(value: Double(index), total: Double(queue.cards.count))
                .accessibilityLabel("Review progress")
            if index < queue.cards.count {
                let card = queue.cards[index]
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        caption("Question")
                        Text(card.prompt).font(.title3).textSelection(.enabled)
                        if revealed {
                            Divider().padding(.vertical, 6)
                            caption("Answer")
                            Text(card.answer).font(.body).textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
                .id(card.id)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                Text(failed ? "Couldn’t save the rating. Try again before moving on."
                            : "Each rating saves immediately and updates the review date.")
                    .font(.caption).foregroundStyle(failed ? Color.red : Color.secondary)
                HStack {
                    Button("End Session") { dismiss() }.keyboardShortcut(.cancelAction)
                    Spacer()
                    if revealed {
                        Button("Again") { submit(card, rating: .again) }
                            .keyboardShortcut("1", modifiers: []).help("Review in 10 minutes (1)")
                        Button("Got It") { submit(card, rating: .gotIt) }
                            .keyboardShortcut("2", modifiers: []).buttonStyle(.borderedProminent)
                            .help("Schedule a later review (2)")
                    } else {
                        Button("Reveal Answer") { revealed = true }.keyboardShortcut(.defaultAction)
                    }
                }
            } else {
                ContentUnavailableView("Session complete", systemImage: "checkmark.circle",
                                       description: Text("\(gotIt) got it • \(index - gotIt) to try again. Review progress was saved on this Mac."))
                HStack {
                    Spacer()
                    Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(22).frame(width: 570, height: 430)
    }

    private func caption(_ text: String) -> some View {
        Text(text.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    private func submit(_ card: Flashcard, rating: Rating) {
        guard rate(card.id, rating) else { failed = true; return }
        if case .gotIt = rating { gotIt += 1 }
        failed = false
        revealed = false
        index += 1
    }
}
