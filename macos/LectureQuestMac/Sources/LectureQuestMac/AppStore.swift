import Foundation
import Observation

/// Single source of truth. Persists to ~/Library/Application Support/LectureQuest/data.json.
@MainActor
@Observable
final class AppStore {
    private(set) var data: AppData
    var lastError: String?
    var toastAchievements: [AchievementDef] = []

    private(set) var model: String
    private(set) var apiKey: String

    var profile: UserProfile { data.profile }
    var lectures: [Lecture] { data.lectures.sorted { $0.date > $1.date } }
    var topicStats: [TopicStats] { data.topicStats }

    init() {
        model = UserDefaults.standard.string(forKey: "claudeModel") ?? ClaudeClient.defaultModel
        apiKey = Keychain.get("anthropic") ?? ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
        data = AppData()
        switch Self.load() {
        case .success(let loaded): data = loaded ?? AppData()
        case .failure(let err):
            // Never silently wipe progress: keep a copy of the unreadable file.
            let backup = Self.storeURL.deletingLastPathComponent()
                .appendingPathComponent("data.unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: Self.storeURL, to: backup)
            lastError = "Couldn't read saved data (\(err.localizedDescription)). A copy was kept at \(backup.path)."
        }
        refreshStreakIfBroken()
    }

    // MARK: Persistence

    static var storeURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LectureQuest", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("data.json")
    }

    /// .success(nil) = first launch; .failure = file exists but can't be decoded.
    private static func load() -> Result<AppData?, Error> {
        guard let d = try? Data(contentsOf: storeURL) else { return .success(nil) }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return Result { try dec.decode(AppData.self, from: d) }.map { Optional($0) }
    }

    func save() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try enc.encode(data).write(to: Self.storeURL, options: .atomic)
        } catch {
            lastError = "Couldn't save your progress: \(error.localizedDescription)"
        }
    }

    // MARK: API key

    func setAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        Keychain.set(trimmed, for: "anthropic")
        apiKey = trimmed
    }

    func setModel(_ m: String) {
        let trimmed = m.trimmingCharacters(in: .whitespacesAndNewlines)
        model = trimmed.isEmpty ? ClaudeClient.defaultModel : trimmed
        UserDefaults.standard.set(model, forKey: "claudeModel")
    }

    var hasAPIKey: Bool { !apiKey.isEmpty }

    private var claude: ClaudeClient { ClaudeClient(apiKey: apiKey, model: model) }

    // MARK: Lectures

    @discardableResult
    func addLecture(title: String, content: String) -> Lecture {
        let lecture = Lecture(title: title.isEmpty ? "Untitled lecture" : title, content: content)
        data.lectures.append(lecture)
        _ = unlock()
        save()
        return lecture
    }

    func recordBatchImport(count: Int) {
        data.profile.maxBatchImport = max(data.profile.maxBatchImport, count)
        _ = unlock()
        save()
    }

    func lecture(_ id: UUID) -> Lecture? { data.lectures.first { $0.id == id } }

    func rename(_ id: UUID, to title: String) {
        guard let i = data.lectures.firstIndex(where: { $0.id == id }) else { return }
        data.lectures[i].title = title
        save()
    }

    func delete(_ id: UUID) {
        data.lectures.removeAll { $0.id == id }
        data.topicStats.removeAll { $0.lectureID == id }
        save()
    }

    /// Generates (or regenerates) the quiz + skills for a lecture via Claude.
    func generateQuiz(for id: UUID) async throws {
        guard let l = lecture(id) else { return }
        let (qs, skills) = try await claude.generateLectureQuiz(content: l.content)
        guard let i = data.lectures.firstIndex(where: { $0.id == id }) else { return }
        data.lectures[i].questions = qs
        if !skills.isEmpty {
            let prof = data.lectures[i].lastReviewed == nil ? Proficiency.developing : Proficiency(accuracy: data.lectures[i].reviewScore)
            data.lectures[i].skills = skills.map { var s = $0; s.proficiency = prof; return s }
        }
        save()
    }

    func startLectureQuiz(_ id: UUID) -> QuizSession? {
        guard let l = lecture(id), !l.questions.isEmpty else { return nil }
        return QuizSession(kind: .lecture(id), title: l.title, questions: l.questions.shuffled())
    }

    // MARK: Daily quiz (spaced repetition)

    var dueTopics: [TopicStats] {
        let today = Calendar.current.startOfDay(for: .now)
        return data.topicStats.filter { Calendar.current.startOfDay(for: $0.nextDue) <= today }
    }

    var dailyDoneToday: Bool { data.profile.lastDailyQuizDay == GameEngine.dayKey() }

    /// Top-10 topics by priority. Falls back to the weakest topics when nothing is due yet.
    func dailyPlan(limit: Int = 10) -> [PlannedTopic] {
        var pool = dueTopics
        if pool.isEmpty { pool = data.topicStats.filter { $0.lastScore < 80 } }
        var seen = Set<String>()
        return pool
            .map { ($0, GameEngine.priority($0)) }
            .sorted { $0.1 > $1.1 }
            .filter { seen.insert($0.0.topic.lowercased()).inserted }
            .prefix(limit)
            .map { PlannedTopic(topic: $0.0.topic, lectureID: $0.0.lectureID, lectureTitle: $0.0.lectureTitle,
                                priority: $0.1, reason: GameEngine.reason(for: $0.0)) }
    }

    func startDailyQuiz(_ plan: [PlannedTopic]) async throws -> QuizSession {
        var seen = Set<UUID>()
        var excerpts: [(title: String, excerpt: String)] = []
        for t in plan where excerpts.count < 5 {
            guard seen.insert(t.lectureID).inserted, let l = lecture(t.lectureID) else { continue }
            excerpts.append((title: l.title, excerpt: String(l.content.prefix(2000))))
        }
        let qs = try await claude.generateDailyQuiz(topics: plan, excerpts: excerpts,
                                                    streak: data.profile.currentStreak,
                                                    averageConfidence: averageConfidence)
        return QuizSession(kind: .daily(plan), title: "Daily Review", questions: qs)
    }

    var averageConfidence: Double {
        let rated = data.lectures.map(\.confidenceRating).filter { $0 > 0 }
        return rated.isEmpty ? 0 : Double(rated.reduce(0, +)) / Double(rated.count)
    }

    // MARK: Power-ups

    func useHint(in s: QuizSession) {
        guard data.profile.powerUps.hints > 0, !s.revealed else { return }
        data.profile.powerUps.hints -= 1
        data.profile.powerUpsUsed.hints = true
        s.applyHint()
        save()
    }

    func useSecondChance(in s: QuizSession) {
        guard data.profile.powerUps.secondChance > 0, !s.revealed, !s.secondChanceArmed else { return }
        data.profile.powerUps.secondChance -= 1
        data.profile.powerUpsUsed.secondChance = true
        s.armSecondChance()
        save()
    }

    func activateDoubleXP() {
        data.profile.powerUps.doubleXP = true
        save()
    }

    // MARK: Finishing a quiz

    @discardableResult
    func finish(_ s: QuizSession, confidence: Int) -> QuizOutcome {
        let now = Date.now
        var p = data.profile
        let total = s.questions.count
        let correct = s.correctCount
        let percent = total == 0 ? 0 : Int((Double(correct) / Double(total) * 100).rounded())
        let perfect = total > 0 && correct == total
        let oldLevel = p.level

        touchStreak(&p, now: now)

        // Improvement vs previous attempt (lecture quizzes only).
        var improvement = 0
        var isImprovement = false
        if case let .lecture(id) = s.kind, let prev = lecture(id)?.attempts.last?.score {
            improvement = percent - prev
            isImprovement = percent > prev
            p.consecutiveImprovements = isImprovement ? p.consecutiveImprovements + 1 : 0
        }

        let usedDouble = p.powerUps.doubleXP
        let xp = GameEngine.quizXP(correct: correct, total: total, confidence: confidence,
                                   isImprovement: isImprovement, streak: p.currentStreak, doubleXP: usedDouble)
        if usedDouble { p.powerUps.doubleXP = false; p.powerUpsUsed.doubleXP = true }
        p.totalXP += xp
        p.quizzesCompleted += 1
        if perfect {
            p.perfectScores += 1
            p.perfectStreak += 1
            p.powerUps.secondChance = min(10, p.powerUps.secondChance + 1)
        } else {
            p.perfectStreak = 0
        }

        // Per-topic scores -> spaced repetition.
        var byTopic: [String: (right: Int, total: Int)] = [:]
        for (i, q) in s.questions.enumerated() {
            var e = byTopic[q.topic, default: (0, 0)]
            e.total += 1
            if s.answers[i] == true { e.right += 1 }
            byTopic[q.topic] = e
        }
        let incorrect = s.questions.enumerated().filter { s.answers[$0.offset] != true }.map(\.element.topic)
        var lectureScores: [UUID: (right: Int, total: Int)] = [:]

        for (topic, r) in byTopic {
            let score = Int((Double(r.right) / Double(max(1, r.total)) * 100).rounded())
            let lectureID: UUID
            switch s.kind {
            case let .lecture(id): lectureID = id
            case let .daily(plan):
                lectureID = plan.first { $0.topic.caseInsensitiveCompare(topic) == .orderedSame }?.lectureID
                    ?? data.topicStats.first { $0.topic.caseInsensitiveCompare(topic) == .orderedSame }?.lectureID
                    ?? plan.first?.lectureID ?? UUID()
            }
            var lr = lectureScores[lectureID, default: (0, 0)]
            lr.right += r.right; lr.total += r.total
            lectureScores[lectureID] = lr
            updateTopic(topic, lectureID: lectureID, score: score, now: now)
        }

        // Lecture records.
        for (lid, r) in lectureScores {
            guard let i = data.lectures.firstIndex(where: { $0.id == lid }) else { continue }
            let lp = Int((Double(r.right) / Double(max(1, r.total)) * 100).rounded())
            let prev = data.lectures[i].attempts.last?.score
            var l = data.lectures[i]
            l.attempts.append(QuizAttempt(date: now, score: lp, xpEarned: xp, improvement: prev.map { lp - $0 } ?? 0,
                                          isDaily: { if case .daily = s.kind { return true } else { return false } }()))
            l.reviewScore = lp
            l.bestScore = max(l.bestScore, lp)
            l.xpEarned += xp
            l.lastReviewed = now
            if case .lecture = s.kind {
                l.incorrectTopics = Array(Set(incorrect)).sorted()
                l.confidenceRating = confidence
            }
            let prof = Proficiency(accuracy: lp)
            l.skills = l.skills.map { var sk = $0; sk.proficiency = prof; return sk }
            data.lectures[i] = l
        }

        // Daily quiz bookkeeping.
        if case .daily = s.kind {
            let today = GameEngine.dayKey(now)
            if p.lastDailyQuizDay != today {
                p.dailyQuizStreak = p.lastDailyQuizDay == GameEngine.yesterdayKey(now) ? p.dailyQuizStreak + 1 : 1
            }
            p.lastDailyQuizDay = today
            p.dailyQuizzesCompleted += 1
            if perfect { p.dailyPerfectStreak += 1; p.hadDailyPerfect = true } else { p.dailyPerfectStreak = 0 }
        }

        // Level-up rewards (same as the web app; "Streak Freeze" becomes a Second Chance here).
        var rewards: [String] = []
        let newLevel = GameEngine.level(forXP: p.totalXP)
        if newLevel > oldLevel {
            if newLevel == 5 { p.powerUps.secondChance += 1; rewards.append("+1 Second Chance") }
            if newLevel % 3 == 0 { p.powerUps.hints += 1; rewards.append("+1 Hint") }
            if Double.random(in: 0..<1) < 0.2 { p.powerUps.doubleXP = true; rewards.append("Double XP (next quiz)") }
        }

        data.profile = p
        let unlocked = unlock(atQuizCompletion: true, now: now)
        let finalLevel = data.profile.level
        save()

        let outcome = QuizOutcome(
            correct: correct, total: total, percent: percent, xpEarned: xp, improvement: improvement,
            incorrectTopics: Array(Set(incorrect)).sorted(), newAchievements: unlocked,
            leveledUpTo: finalLevel > oldLevel ? finalLevel : nil, levelRewards: rewards,
            message: GameEngine.performanceMessage(percent: percent, improvement: improvement))
        s.outcome = outcome
        return outcome
    }

    private func updateTopic(_ topic: String, lectureID: UUID, score: Int, now: Date) {
        let title = lecture(lectureID)?.title ?? "Lecture"
        if let i = data.topicStats.firstIndex(where: {
            $0.lectureID == lectureID && $0.topic.caseInsensitiveCompare(topic) == .orderedSame
        }) {
            var t = data.topicStats[i]
            let newStreak = score >= 70 ? t.streak + 1 : 0
            let r = GameEngine.nextReview(easeFactor: t.easeFactor, score: score, streak: newStreak, from: now)
            t.streak = newStreak
            t.easeFactor = r.easeFactor
            t.interval = r.interval
            t.nextDue = r.nextDue
            t.lastScore = score
            t.lastReviewed = now
            t.reviewCount += 1
            t.scoreHistory.append(score)
            data.topicStats[i] = t
        } else {
            let streak = score >= 70 ? 1 : 0
            let r = GameEngine.nextReview(easeFactor: 2.5, score: score, streak: streak, from: now)
            data.topicStats.append(TopicStats(
                topic: topic, lectureID: lectureID, lectureTitle: title, lastReviewed: now, lastScore: score,
                easeFactor: r.easeFactor, interval: r.interval, nextDue: r.nextDue, streak: streak,
                scoreHistory: [score]))
        }
    }

    private func touchStreak(_ p: inout UserProfile, now: Date) {
        let today = GameEngine.dayKey(now)
        if p.lastActivityDay != today {
            p.currentStreak = p.lastActivityDay == GameEngine.yesterdayKey(now) ? p.currentStreak + 1 : 1
            p.longestStreak = max(p.longestStreak, p.currentStreak)
            p.lastActivityDay = today
        }
        if Calendar.current.component(.hour, from: now) < 9 && p.lastMorningDay != today {
            p.morningStreak = p.lastMorningDay == GameEngine.yesterdayKey(now) ? p.morningStreak + 1 : 1
            p.lastMorningDay = today
        }
    }

    /// Streaks reset if a full day was skipped (checked on launch).
    private func refreshStreakIfBroken() {
        guard let last = data.profile.lastActivityDay,
              last != GameEngine.dayKey(), last != GameEngine.yesterdayKey() else { return }
        data.profile.currentStreak = 0
    }

    @discardableResult
    private func unlock(atQuizCompletion: Bool = false, now: Date = .now) -> [AchievementDef] {
        // Copy out first: passing &data.profile while reading data.lectures would be an exclusivity violation.
        var profile = data.profile
        let lectures = data.lectures, topics = data.topicStats
        let new = GameEngine.unlockNew(profile: &profile, lectures: lectures, topics: topics,
                                       now: now, atQuizCompletion: atQuizCompletion)
        data.profile = profile
        if !new.isEmpty { toastAchievements.append(contentsOf: new) }
        return new
    }

    // MARK: Skills

    struct AggregatedSkill: Identifiable {
        var id: String { skill.id }
        var skill: Skill
        var lectures: [String]
    }

    var aggregatedSkills: [AggregatedSkill] {
        var map: [String: AggregatedSkill] = [:]
        for l in data.lectures {
            for s in l.skills {
                if var e = map[s.id] {
                    if s.proficiency > e.skill.proficiency { e.skill.proficiency = s.proficiency }
                    e.skill.relevantCareers = Array(Set(e.skill.relevantCareers + s.relevantCareers)).sorted()
                    e.lectures.append(l.title)
                    map[s.id] = e
                } else {
                    map[s.id] = AggregatedSkill(skill: s, lectures: [l.title])
                }
            }
        }
        return map.values.sorted { ($0.skill.proficiency, $0.skill.name) > ($1.skill.proficiency, $1.skill.name) }
    }

    func skillsCSV() -> String {
        func esc(_ s: String) -> String { "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" }
        var rows = ["Skill,Category,Proficiency,Description,Relevant Careers,Lectures"]
        for a in aggregatedSkills {
            rows.append([a.skill.name, a.skill.category.rawValue, a.skill.proficiency.rawValue, a.skill.description,
                         a.skill.relevantCareers.joined(separator: "; "), a.lectures.joined(separator: "; ")]
                .map(esc).joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    func setDisplayName(_ name: String) {
        data.profile.displayName = name
        save()
    }

    // MARK: Danger zone

    func resetAll() {
        data = AppData()
        save()
    }
}
