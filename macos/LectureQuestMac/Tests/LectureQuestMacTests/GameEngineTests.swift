import XCTest
@testable import LectureQuestMac

final class GameEngineTests: XCTestCase {
    func testLevelFormulaMatchesWebApp() {
        XCTAssertEqual(GameEngine.level(forXP: 0), 1)
        XCTAssertEqual(GameEngine.level(forXP: 399), 1)
        XCTAssertEqual(GameEngine.level(forXP: 400), 2)
        XCTAssertEqual(GameEngine.level(forXP: 2500), 5)
        XCTAssertEqual(GameEngine.xpForNextLevel(1), 400)
    }

    func testQuizXP() {
        // 50 base + 10*10 + 50 perfect + 5*5 confidence = 225
        XCTAssertEqual(GameEngine.quizXP(correct: 10, total: 10, confidence: 5, isImprovement: false, streak: 0, doubleXP: false), 225)
        // 7-day streak => 1.5x ; (50+70+0+15+20+35)*1.5 = 285
        XCTAssertEqual(GameEngine.quizXP(correct: 7, total: 10, confidence: 3, isImprovement: true, streak: 7, doubleXP: false), 285)
        XCTAssertEqual(GameEngine.quizXP(correct: 0, total: 10, confidence: 0, isImprovement: false, streak: 0, doubleXP: true), 100)
    }

    func testSM2() {
        let fail = GameEngine.nextReview(easeFactor: 2.5, score: 30, streak: 0)
        XCTAssertEqual(fail.interval, 1)
        XCTAssertLessThan(fail.easeFactor, 2.5)
        let second = GameEngine.nextReview(easeFactor: 2.5, score: 100, streak: 1)
        XCTAssertEqual(second.interval, 3)
        let later = GameEngine.nextReview(easeFactor: 2.5, score: 100, streak: 3)
        XCTAssertEqual(later.interval, Int((14 * 2.6).rounded()))
        XCTAssertGreaterThanOrEqual(GameEngine.nextReview(easeFactor: 1.3, score: 0, streak: 0).easeFactor, 1.3)
    }

    func testCatalogHasAllAchievements() {
        XCTAssertEqual(AchievementCatalog.all.count, 100)
        XCTAssertEqual(Set(AchievementCatalog.all.map(\.id)).count, 100)
    }

    func testFirstLectureAchievementUnlocks() {
        var p = UserProfile()
        let lecture = Lecture(title: "Test", content: String(repeating: "content ", count: 20))
        let unlocked = GameEngine.unlockNew(profile: &p, lectures: [lecture], topics: [])
        XCTAssertTrue(unlocked.contains { $0.id == "first_lecture" })
        XCTAssertNotNil(p.unlockedAchievements["first_lecture"])
        XCTAssertGreaterThan(p.totalXP, 0)
    }

    func testLenientJSONParsing() throws {
        let raw = """
        ```json
        {"questions":[{"question":"Q?","options":["a","b","c","d"],"correct":2,"explanation":"e","topic":"T"},
                      {"question":"bad","options":["a"],"correct":0}],
         "skills":[{"name":"Analysis","description":"d","category":"weird","relevantCareers":["X"]}]}
        ```
        """
        let obj = try ClaudeClient.parseJSON(raw) as? [String: Any]
        let qs = ClaudeClient.questions(from: obj?["questions"], fallbackTopic: "G")
        XCTAssertEqual(qs.count, 1)
        XCTAssertEqual(qs[0].correct, 2)
        let skills = ClaudeClient.skills(from: obj?["skills"])
        XCTAssertEqual(skills.first?.category, .cognitive)
    }
}
