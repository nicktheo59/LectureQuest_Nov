import SwiftUI

struct QuizView: View {
    @Environment(AppStore.self) private var store
    @Bindable var session: QuizSession
    var close: () -> Void
    @State private var askingConfidence = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                if let outcome = session.outcome {
                    ResultsView(session: session, outcome: outcome, close: close)
                } else if askingConfidence {
                    ConfidenceView(rating: $session.confidence) {
                        store.finish(session, confidence: session.confidence)
                    }
                } else {
                    questionView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title).font(Theme.serif(20)).lineLimit(1)
                if session.outcome == nil && !askingConfidence {
                    Text("Question \(session.index + 1) of \(session.questions.count)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if store.profile.powerUps.doubleXP {
                Label("2× XP", systemImage: "bolt.fill").foregroundStyle(Theme.gold).font(.caption.weight(.semibold))
            }
            Button(session.outcome == nil ? "Quit" : "Close") { close() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(16)
        .overlay(alignment: .bottom) {
            if session.outcome == nil {
                ProgressView(value: Double(session.answers.count), total: Double(max(1, session.questions.count)))
                    .tint(Theme.forest).padding(.horizontal, 16).offset(y: 6)
            }
        }
    }

    private var questionView: some View {
        let q = session.current
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(q.topic.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(Theme.forest).tracking(1)
                Text(q.question).font(Theme.serif(22)).fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 10) {
                    ForEach(q.options.indices, id: \.self) { i in
                        OptionRow(letter: ["A", "B", "C", "D"][min(i, 3)], text: q.options[i],
                                  state: optionState(i))
                            .onTapGesture { session.choose(i) }
                    }
                }

                if session.secondChanceArmed && !session.revealed {
                    Label("Second chance armed — a wrong answer can be retried once.", systemImage: "arrow.uturn.backward.circle")
                        .font(.callout).foregroundStyle(Theme.forest)
                }

                if session.revealed {
                    let ok = session.answers[session.index] == true
                    Card {
                        Label(ok ? "Correct" : "Not quite", systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.headline).foregroundStyle(ok ? Theme.success : .red)
                        Text(q.explanation).fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack {
                    Button {
                        store.useHint(in: session)
                    } label: { Label("Hint (\(store.profile.powerUps.hints))", systemImage: "lightbulb") }
                    .disabled(store.profile.powerUps.hints == 0 || session.revealed || session.eliminated.count >= 2)

                    Button {
                        store.useSecondChance(in: session)
                    } label: { Label("Second chance (\(store.profile.powerUps.secondChance))", systemImage: "arrow.uturn.backward") }
                    .disabled(store.profile.powerUps.secondChance == 0 || session.revealed || session.secondChanceArmed)

                    Spacer()

                    if !session.revealed {
                        Button("Check answer") { session.submit() }
                            .buttonStyle(.borderedProminent)
                            .disabled(session.selected == nil)
                            .keyboardShortcut(.defaultAction)
                    } else if session.isLast {
                        Button("Finish") { askingConfidence = true }
                            .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    } else {
                        Button("Next question") { session.next() }
                            .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    }
                }
            }
            .padding(28)
        }
        .background(KeyboardShortcuts(session: session))
    }

    private func optionState(_ i: Int) -> OptionRow.Appearance {
        let q = session.current
        if session.eliminated.contains(i) { return .eliminated }
        if session.revealed {
            if i == q.correct { return .correct }
            if i == session.selected { return .wrong }
            return .idle
        }
        return session.selected == i ? .selected : .idle
    }
}

/// 1–4 / A–D keys pick an answer.
private struct KeyboardShortcuts: View {
    var session: QuizSession
    var body: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { i in
                Button("") { session.choose(i) }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: [])
                    .opacity(0).frame(width: 0, height: 0)
            }
        }
    }
}

struct OptionRow: View {
    enum Appearance { case idle, selected, correct, wrong, eliminated }
    var letter: String
    var text: String
    var state: Appearance

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(letter)
                .font(.headline)
                .frame(width: 28, height: 28)
                .background(badge, in: Circle())
                .foregroundStyle(state == .idle || state == .eliminated ? Color.primary : .white)
            Text(text).fixedSize(horizontal: false, vertical: true)
                .strikethrough(state == .eliminated)
            Spacer(minLength: 0)
        }
        .padding(14)
        .contentShape(Rectangle())
        .background(fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(stroke, lineWidth: 1.5))
        .opacity(state == .eliminated ? 0.4 : 1)
        .animation(.easeOut(duration: 0.15), value: state)
    }

    private var badge: Color {
        switch state {
        case .selected: Theme.forest
        case .correct: Theme.success
        case .wrong: .red
        default: Color.secondary.opacity(0.15)
        }
    }
    private var fill: Color {
        switch state {
        case .selected: Theme.forest.opacity(0.08)
        case .correct: Theme.success.opacity(0.12)
        case .wrong: Color.red.opacity(0.10)
        default: Color.secondary.opacity(0.05)
        }
    }
    private var stroke: Color {
        switch state {
        case .selected: Theme.forest
        case .correct: Theme.success
        case .wrong: .red
        default: Color.secondary.opacity(0.2)
        }
    }
}

struct ConfidenceView: View {
    @Binding var rating: Int
    var submit: () -> Void
    private let labels = ["Lost", "Shaky", "Getting there", "Confident", "Nailed it"]

    var body: some View {
        VStack(spacing: 20) {
            Text("How confident do you feel about this material?").font(Theme.serif(24))
            Text("Honest ratings earn XP too (+5 XP per point).").foregroundStyle(.secondary)
            HStack(spacing: 12) {
                ForEach(1...5, id: \.self) { i in
                    Button { rating = i } label: {
                        VStack(spacing: 6) {
                            Image(systemName: i <= rating ? "star.fill" : "star").font(.title)
                            Text(labels[i - 1]).font(.caption)
                        }
                        .frame(width: 96, height: 76)
                        .foregroundStyle(i <= rating ? Theme.gold : .secondary)
                        .background(Color.secondary.opacity(i == rating ? 0.12 : 0.05), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(KeyEquivalent(Character("\(i)")), modifiers: [])
                }
            }
            Button("See results", action: submit)
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(rating == 0).keyboardShortcut(.defaultAction)
        }
        .padding(32)
    }
}

struct ResultsView: View {
    var session: QuizSession
    var outcome: QuizOutcome
    var close: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                if let lvl = outcome.leveledUpTo {
                    VStack(spacing: 6) {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 44)).foregroundStyle(Theme.gold)
                        Text("Level \(lvl) — \(GameEngine.levelTitle(lvl))").font(Theme.serif(26))
                        if !outcome.levelRewards.isEmpty {
                            Text("Rewards: " + outcome.levelRewards.joined(separator: ", ")).foregroundStyle(.secondary)
                        }
                    }
                    .padding().frame(maxWidth: .infinity)
                    .background(Theme.lavender.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
                }

                Text("\(outcome.percent)%").font(Theme.serif(64)).foregroundStyle(outcome.percent >= 70 ? Theme.success : .orange)
                Text(outcome.message).font(Theme.serif(20))
                HStack(spacing: 12) {
                    StatPill(symbol: "checkmark.circle", value: "\(outcome.correct)/\(outcome.total)", label: "Correct")
                    StatPill(symbol: "bolt.fill", value: "+\(outcome.xpEarned)", label: "XP earned", tint: Theme.gold)
                    if outcome.improvement != 0 {
                        StatPill(symbol: outcome.improvement > 0 ? "arrow.up.right" : "arrow.down.right",
                                 value: "\(outcome.improvement > 0 ? "+" : "")\(outcome.improvement)", label: "vs last attempt")
                    }
                }

                if !outcome.newAchievements.isEmpty {
                    Card {
                        Text("Achievements unlocked").font(.headline)
                        ForEach(outcome.newAchievements) { a in
                            Label("\(a.name) — \(a.detail)  (+\(a.xpReward) XP)", systemImage: a.symbol)
                                .foregroundStyle(Theme.gold)
                        }
                    }
                }

                if !outcome.incorrectTopics.isEmpty {
                    Card {
                        Text("Scheduled for extra review").font(.headline)
                        Text(outcome.incorrectTopics.joined(separator: " · ")).foregroundStyle(.secondary)
                    }
                }

                Button("Done", action: close).buttonStyle(.borderedProminent).controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(32)
        }
    }
}
