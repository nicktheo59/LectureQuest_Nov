import Foundation

// MARK: - Quiz content

struct Question: Codable, Identifiable, Hashable {
    var id = UUID()
    var question: String
    var options: [String]
    var correct: Int
    var explanation: String
    var topic: String
}

enum SkillCategory: String, Codable, CaseIterable {
    case cognitive, technical, communication, interpersonal, organizational
}

enum Proficiency: String, Codable, Comparable {
    case developing, intermediate, proficient

    /// Same thresholds as the web app: >=85 proficient, 60–84 intermediate, else developing.
    init(accuracy: Int) {
        switch accuracy {
        case 85...: self = .proficient
        case 60..<85: self = .intermediate
        default: self = .developing
        }
    }

    private var rank: Int {
        switch self {
        case .developing: return 0
        case .intermediate: return 1
        case .proficient: return 2
        }
    }
    static func < (a: Proficiency, b: Proficiency) -> Bool { a.rank < b.rank }
}

struct Skill: Codable, Hashable, Identifiable {
    var id: String { name.lowercased() }
    var name: String
    var description: String
    var category: SkillCategory
    var relevantCareers: [String]
    var proficiency: Proficiency = .developing
}

// MARK: - Lectures

struct QuizAttempt: Codable, Hashable {
    var date: Date
    var score: Int          // percent 0–100
    var xpEarned: Int
    var improvement: Int    // percentage points vs previous attempt
    var isDaily: Bool
}

struct Lecture: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var date: Date = .now
    var content: String
    var questions: [Question] = []      // most recently generated quiz (cached)
    var skills: [Skill] = []
    var reviewScore: Int = 0            // last quiz accuracy %
    var bestScore: Int = 0
    var xpEarned: Int = 0
    var incorrectTopics: [String] = []
    var confidenceRating: Int = 0
    var attempts: [QuizAttempt] = []
    var lastReviewed: Date?

    var needsReview: Bool { lastReviewed == nil || reviewScore < 80 }
    var wordCount: Int { content.split(whereSeparator: \.isWhitespace).count }
}

// MARK: - Spaced repetition

struct TopicStats: Codable, Identifiable, Hashable {
    var id: String { "\(lectureID.uuidString)|\(topic.lowercased())" }
    var topic: String
    var lectureID: UUID
    var lectureTitle: String
    var lastReviewed: Date
    var lastScore: Int
    var reviewCount: Int = 1
    var easeFactor: Double = 2.5
    var interval: Int = 1
    var nextDue: Date
    var streak: Int = 0
    var scoreHistory: [Int] = []

    var isMastered: Bool { lastScore >= 80 && streak >= 2 }
}

enum ReviewReason: String, Codable { case overdue, due, weak, new }

struct PlannedTopic: Codable, Hashable {
    var topic: String
    var lectureID: UUID
    var lectureTitle: String
    var priority: Double
    var reason: ReviewReason
}

// MARK: - Profile

struct PowerUps: Codable, Hashable {
    var hints: Int = 3
    var secondChance: Int = 1
    var doubleXP: Bool = false
}

struct PowerUpsUsed: Codable, Hashable {
    var hints = false
    var secondChance = false
    var doubleXP = false
    var all: Bool { hints && secondChance && doubleXP }
}

struct UserProfile: Codable, Hashable {
    var displayName: String = NSFullUserName()
    var totalXP: Int = 0
    var currentStreak: Int = 0
    var longestStreak: Int = 0
    var lastActivityDay: String?            // yyyy-MM-dd in local time
    var morningStreak: Int = 0
    var lastMorningDay: String?
    var powerUps = PowerUps()
    var powerUpsUsed = PowerUpsUsed()
    var quizzesCompleted: Int = 0
    var perfectScores: Int = 0
    var perfectStreak: Int = 0
    var dailyQuizzesCompleted: Int = 0
    var dailyQuizStreak: Int = 0
    var dailyPerfectStreak: Int = 0
    var lastDailyQuizDay: String?
    var hadDailyPerfect = false
    var consecutiveImprovements: Int = 0
    var maxBatchImport: Int = 0
    var unlockedAchievements: [String: Date] = [:]

    var level: Int { GameEngine.level(forXP: totalXP) }
}

/// Everything persisted to disk.
struct AppData: Codable {
    var schemaVersion = 1
    var profile = UserProfile()
    var lectures: [Lecture] = []
    var topicStats: [TopicStats] = []
}

// MARK: - Achievements

enum AchievementCategory: String, CaseIterable, Codable {
    case studyMilestones, perfectScores, streakMasters, timeBased, improvement,
         topicMastery, social, dailyQuiz, special

    var title: String {
        switch self {
        case .studyMilestones: "Study Milestones"
        case .perfectScores: "Perfect Scores"
        case .streakMasters: "Streak Masters"
        case .timeBased: "Time Warriors"
        case .improvement: "Growth Journey"
        case .topicMastery: "Topic Mastery"
        case .social: "Social & Competition"
        case .dailyQuiz: "Daily Quiz"
        case .special: "Special"
        }
    }

    var symbol: String {
        switch self {
        case .studyMilestones: "book"
        case .perfectScores: "target"
        case .streakMasters: "flame"
        case .timeBased: "clock"
        case .improvement: "chart.line.uptrend.xyaxis"
        case .topicMastery: "brain"
        case .social: "person.2"
        case .dailyQuiz: "calendar"
        case .special: "sparkles"
        }
    }
}

enum AchievementRule: Hashable {
    case lectures(Int), quizzes(Int), xp(Int), perfects(Int), perfectStreak(Int), perfectOnFirst
    case streak(Int), longestStreak(Int), streakComeback, morningStreak(Int)
    case hours(Int, Int), weekdays([Int]), dayOfMonth(Int)
    case improvement(Int), perfectTurnaround, bounceBack, consecutiveImprovements(Int)
    case mastered(Int), masteredLectures(Int), topicReviews(Int), specialist, renaissance
    case dailies(Int), dailyStreak(Int), dailyPerfectStreak(Int), dailyPerfect
    case confidenceFives(Int), batchImport(Int), level(Int), allPowerUps
    case webOnly   // friends / leaderboard / calendar — only exist in the hosted web app
}

struct AchievementDef: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String
    let symbol: String
    let category: AchievementCategory
    let xpReward: Int
    let maxProgress: Int
    let rule: AchievementRule
}
