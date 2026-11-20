import Foundation
import Observation

enum QuizKind: Hashable {
    case lecture(UUID)
    case daily([PlannedTopic])
}

struct QuizOutcome {
    var correct: Int
    var total: Int
    var percent: Int
    var xpEarned: Int
    var improvement: Int
    var incorrectTopics: [String]
    var newAchievements: [AchievementDef]
    var leveledUpTo: Int?
    var levelRewards: [String]
    var message: String
}

/// State for one quiz run. Owned by the view; results are committed via AppStore.finish(_:confidence:).
@Observable
final class QuizSession: Identifiable {
    let id = UUID()
    let kind: QuizKind
    let title: String
    let questions: [Question]

    var index = 0
    var selected: Int?
    var revealed = false
    var answers: [Int: Bool] = [:]       // question index -> correct?
    var eliminated: Set<Int> = []        // options removed by a hint
    var secondChanceArmed = false        // a wrong answer may be retried once
    var usedHint = false, usedSecondChance = false
    var confidence = 0
    var outcome: QuizOutcome?

    init(kind: QuizKind, title: String, questions: [Question]) {
        self.kind = kind
        self.title = title
        self.questions = questions
    }

    var current: Question { questions[index] }
    var isLast: Bool { index == questions.count - 1 }
    var finishedAnswering: Bool { answers.count == questions.count }
    var correctCount: Int { answers.values.filter { $0 }.count }

    func choose(_ option: Int) {
        guard !revealed, !eliminated.contains(option) else { return }
        selected = option
    }

    func submit() {
        guard let s = selected, !revealed else { return }
        let ok = s == current.correct
        if !ok && secondChanceArmed {
            // Burn the second chance: eliminate the wrong pick and let them try again.
            secondChanceArmed = false
            eliminated.insert(s)
            selected = nil
            return
        }
        answers[index] = ok
        revealed = true
    }

    func next() {
        guard revealed, !isLast else { return }
        index += 1
        selected = nil
        revealed = false
        eliminated = []
        secondChanceArmed = false
    }

    /// Removes two wrong options.
    func applyHint() {
        let wrong = current.options.indices.filter { $0 != current.correct && !eliminated.contains($0) }
        for i in wrong.shuffled().prefix(2) { eliminated.insert(i) }
        if selected.map(eliminated.contains) == true { selected = nil }
        usedHint = true
    }

    func armSecondChance() {
        secondChanceArmed = true
        usedSecondChance = true
    }
}
