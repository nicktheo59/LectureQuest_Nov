import Foundation

/// Pure game logic, ported 1:1 from client/src/lib/game-utils.ts and shared/schema.ts
/// so XP, levels, and spaced repetition behave exactly like the web app.
enum GameEngine {

    // MARK: Levels  (Level = floor(sqrt(XP / 100)), minimum 1)

    static func level(forXP xp: Int) -> Int {
        max(1, Int((Double(xp) / 100).squareRoot()))
    }

    static func xpForNextLevel(_ level: Int) -> Int { (level + 1) * (level + 1) * 100 }

    static func xpAtStartOfLevel(_ level: Int) -> Int { level <= 1 ? 0 : level * level * 100 }

    /// 0…1 progress through the current level.
    static func levelProgress(xp: Int) -> Double {
        let lvl = level(forXP: xp)
        let start = xpAtStartOfLevel(lvl), end = xpForNextLevel(lvl)
        return min(1, max(0, Double(xp - start) / Double(end - start)))
    }

    static let levelTitles: [Int: String] = [
        1: "Knowledge Novice", 2: "Study Starter", 3: "Learning Explorer", 4: "Quiz Challenger",
        5: "Knowledge Apprentice", 6: "Study Scholar", 7: "Knowledge Warrior", 8: "Learning Champion",
        9: "Quiz Master", 10: "Knowledge Master", 11: "Wisdom Seeker", 12: "Grand Scholar",
        13: "Learning Legend", 14: "Knowledge Sage", 15: "Ultimate Master",
    ]

    static func levelTitle(_ level: Int) -> String { levelTitles[min(level, 15)] ?? "Ultimate Master" }

    // MARK: XP

    static func quizXP(correct: Int, total: Int, confidence: Int, isImprovement: Bool,
                       streak: Int, doubleXP: Bool) -> Int {
        var xp = 50.0 + Double(correct * 10)
        if total > 0 && correct == total { xp += 50 }
        xp += Double(confidence * 5)
        if isImprovement { xp += 20 }
        xp += Double(streak * 5)
        if streak >= 30 { xp *= 2 } else if streak >= 7 { xp *= 1.5 }
        if doubleXP { xp *= 2 }
        return Int(xp)
    }

    static func streakMultiplierLabel(_ streak: Int) -> String? {
        streak >= 30 ? "2x XP" : streak >= 7 ? "1.5x XP" : nil
    }

    static func performanceMessage(percent: Int, improvement: Int) -> String {
        if improvement >= 15 { return "+\(improvement)% improvement! You're levelling up!" }
        if percent == 100 { return "Flawless. You're unstoppable." }
        if percent >= 70 { return "Solid work — keep pushing." }
        return "Growth happens outside comfort zones."
    }

    // MARK: Spaced repetition (SM-2 inspired)

    static let intervals = [1, 3, 7, 14, 30, 60, 90]

    static func nextReview(easeFactor: Double, score: Int, streak: Int, from date: Date = .now)
        -> (easeFactor: Double, interval: Int, nextDue: Date) {
        let quality = Int((Double(score) / 100 * 5).rounded())
        let q = Double(5 - quality)
        let newEase = max(1.3, easeFactor + (0.1 - q * (0.08 + q * 0.02)))
        let interval: Int
        if quality < 3 || streak == 0 { interval = 1 }
        else if streak == 1 { interval = 3 }
        else { interval = Int((Double(intervals[min(streak, intervals.count - 1)]) * newEase).rounded()) }
        let due = Calendar.current.date(byAdding: .day, value: interval, to: Calendar.current.startOfDay(for: date))!
        return (newEase, interval, due)
    }

    static func priority(_ s: TopicStats, today: Date = .now) -> Double {
        let cal = Calendar.current
        let daysSinceDue = cal.dateComponents([.day], from: cal.startOfDay(for: s.nextDue),
                                              to: cal.startOfDay(for: today)).day ?? 0
        var p = 0.0
        if daysSinceDue > 0 { p += 100 + Double(daysSinceDue * 10) }
        if daysSinceDue == 0 { p += 80 }
        p += max(0, 50 - Double(s.lastScore) / 2)
        p += max(0, (2.5 - s.easeFactor) * 20)
        p += max(0, Double(5 - s.streak) * 5)
        return p
    }

    static func reason(for s: TopicStats, today: Date = .now) -> ReviewReason {
        let cal = Calendar.current
        let d = cal.dateComponents([.day], from: cal.startOfDay(for: s.nextDue), to: cal.startOfDay(for: today)).day ?? 0
        if s.reviewCount <= 1 && d <= 0 { return .new }
        if d > 0 { return .overdue }
        if s.lastScore < 70 { return .weak }
        return .due
    }

    // MARK: Dates

    static func dayKey(_ date: Date = .now) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static func yesterdayKey(_ date: Date = .now) -> String {
        dayKey(Calendar.current.date(byAdding: .day, value: -1, to: date)!)
    }

    // MARK: Achievements

    struct Snapshot {
        var profile: UserProfile
        var lectures: [Lecture]
        var topics: [TopicStats]
        var now: Date = .now
        /// Time-of-day achievements only count at the moment a quiz is finished.
        var atQuizCompletion = false
    }

    /// Returns current progress (0…maxProgress) for an achievement.
    static func progress(of a: AchievementDef, in s: Snapshot) -> Int {
        let p = s.profile
        let cal = Calendar.current
        let hour = cal.component(.hour, from: s.now)
        let mastered = s.topics.filter(\.isMastered)
        func bool(_ b: Bool) -> Int { b ? a.maxProgress : 0 }
        func cap(_ v: Int) -> Int { min(a.maxProgress, max(0, v)) }
        let attempts = s.lectures.map { $0.attempts.sorted { $0.date < $1.date } }

        switch a.rule {
        case .lectures: return cap(s.lectures.count)
        case .quizzes: return cap(p.quizzesCompleted)
        case .xp: return cap(p.totalXP)
        case .perfects: return cap(p.perfectScores)
        case .perfectStreak: return cap(p.perfectStreak)
        case .perfectOnFirst: return bool(attempts.contains { $0.first?.score == 100 })
        case .streak: return cap(p.currentStreak)
        case .longestStreak: return cap(p.longestStreak)
        case .streakComeback:
            return bool(p.longestStreak >= 7 && p.currentStreak >= 1 && p.currentStreak < p.longestStreak)
        case .morningStreak: return cap(p.morningStreak)
        case let .hours(from, to): return bool(s.atQuizCompletion && hour >= from && hour < to)
        case let .weekdays(days): return bool(s.atQuizCompletion && days.contains(cal.component(.weekday, from: s.now)))
        case let .dayOfMonth(d): return bool(s.atQuizCompletion && cal.component(.day, from: s.now) == d)
        case let .improvement(pct): return bool(s.lectures.contains { $0.attempts.contains { $0.improvement >= pct } })
        case .perfectTurnaround:
            return bool(attempts.contains { run in zip(run, run.dropFirst()).contains { $0.score < 50 && $1.score == 100 } })
        case .bounceBack:
            return bool(attempts.contains { run in zip(run, run.dropFirst()).contains { $0.score < 50 && $1.score >= 80 } })
        case .consecutiveImprovements: return cap(p.consecutiveImprovements)
        case .mastered: return cap(mastered.count)
        case .masteredLectures: return cap(Set(mastered.map(\.lectureID)).count)
        case .topicReviews: return cap(s.topics.map(\.reviewCount).max() ?? 0)
        case .specialist:
            let byLecture = Dictionary(grouping: s.topics, by: \.lectureID)
            return bool(byLecture.values.contains { !$0.isEmpty && $0.allSatisfy(\.isMastered) })
        case .renaissance: return cap(s.lectures.filter { $0.reviewScore >= 80 }.count)
        case .dailies: return cap(p.dailyQuizzesCompleted)
        case .dailyStreak: return cap(p.dailyQuizStreak)
        case .dailyPerfectStreak: return cap(p.dailyPerfectStreak)
        case .dailyPerfect: return bool(p.hadDailyPerfect)
        case .confidenceFives: return cap(s.lectures.filter { $0.confidenceRating == 5 }.count)
        case .batchImport: return cap(p.maxBatchImport)
        case .level: return cap(p.level)
        case .allPowerUps: return bool(p.powerUpsUsed.all)
        case .webOnly: return 0
        }
    }

    static func isSatisfied(_ a: AchievementDef, in s: Snapshot) -> Bool {
        if case .webOnly = a.rule { return false }
        return progress(of: a, in: s) >= a.maxProgress
    }

    /// Unlocks any newly satisfied achievements (awarding their XP) and returns them.
    /// Loops because achievement XP can itself unlock XP/level achievements.
    static func unlockNew(profile: inout UserProfile, lectures: [Lecture], topics: [TopicStats],
                          now: Date = .now, atQuizCompletion: Bool = false) -> [AchievementDef] {
        var unlocked: [AchievementDef] = []
        var changed = true
        while changed {
            changed = false
            let snap = Snapshot(profile: profile, lectures: lectures, topics: topics, now: now,
                                atQuizCompletion: atQuizCompletion)
            for a in AchievementCatalog.all where profile.unlockedAchievements[a.id] == nil {
                if isSatisfied(a, in: snap) {
                    profile.unlockedAchievements[a.id] = now
                    profile.totalXP += a.xpReward
                    unlocked.append(a)
                    changed = true
                }
            }
        }
        return unlocked
    }
}
