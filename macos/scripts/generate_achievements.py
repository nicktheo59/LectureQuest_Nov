#!/usr/bin/env python3
"""Generate macos/.../AchievementCatalog.swift from the web app's TypeScript sources.

Run from the repo root:  python3 macos/scripts/generate_achievements.py
"""
import re, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
schema = (ROOT / "shared/schema.ts").read_text()
game = (ROOT / "client/src/lib/game-utils.ts").read_text()
OUT = ROOT / "macos/LectureQuestMac/Sources/LectureQuestMac/AchievementCatalog.swift"

block = schema[schema.find("export const ALL_ACHIEVEMENTS"):schema.find("// Initial user profile")]
objs = re.findall(
    r'\{\s*id: "([^"]+)",\s*name: "([^"]+)",\s*description: "([^"]+)",\s*icon: "([^"]+)",'
    r'\s*category: "([^"]+)",\s*xpReward: (\d+),[^}]*?maxProgress: (\d+)', block, re.S)

body = game[game.find("switch (achievement.id)"):game.find("export function extractTopics")]
rules = {m.group(1): m.group(2).strip()
         for m in re.finditer(r'case "([^"]+)":\s*\n\s*shouldUnlock = ([^;]+);', body)}

PATTERNS = [
    (r"^lectureCount >= (\d+)$", ".lectures({})"),
    (r"^ctx.totalQuizzesCompleted >= (\d+)$", ".quizzes({})"),
    (r"^userProfile.totalXP >= (\d+)$", ".xp({})"),
    (r"^perfectScores >= (\d+)$", ".perfects({})"),
    (r"^ctx.perfectStreak >= (\d+)$", ".perfectStreak({})"),
    (r"^userProfile.currentStreak >= (\d+)$", ".streak({})"),
    (r"^userProfile.longestStreak >= (\d+)$", ".longestStreak({})"),
    (r"^ctx.morningStreak >= (\d+)$", ".morningStreak({})"),
    (r"^hasImprovement\((\d+)\)$", ".improvement({})"),
    (r"^ctx.consecutiveImprovements >= (\d+)$", ".consecutiveImprovements({})"),
    (r"^masteredCount >= (\d+)$", ".mastered({})"),
    (r"^ctx.dailyQuizzesCompleted >= (\d+)$", ".dailies({})"),
    (r"^ctx.dailyQuizStreak >= (\d+)$", ".dailyStreak({})"),
    (r"^ctx.dailyPerfectStreak >= (\d+)$", ".dailyPerfectStreak({})"),
    (r"^confidenceRatings >= (\d+)$", ".confidenceFives({})"),
    (r"^ctx.batchUploadCount >= (\d+)$", ".batchImport({})"),
    (r"^userProfile.level >= (\d+)$", ".level({})"),
]
SPECIAL = {
    "perfect_on_first": ".perfectOnFirst", "streak_comeback": ".streakComeback",
    "early_bird": ".hours(0, 8)", "night_owl": ".hours(22, 24)", "lunch_learner": ".hours(12, 13)",
    "late_night": ".hours(0, 3)", "afternoon_ace": ".hours(14, 17)",
    "weekend_warrior": ".weekdays([1, 7])", "monday_motivation": ".weekdays([2])",
    "friday_focus": ".weekdays([6])", "first_of_month": ".dayOfMonth(1)",
    "perfect_turnaround": ".perfectTurnaround", "bouncing_back": ".bounceBack",
    "specialist": ".specialist", "renaissance_learner": ".renaissance",
    # multi-line rules in game-utils.ts, mapped by hand:
    "growth_mindset": ".quizzes(10)", "mastery_journey": ".topicReviews(5)",
    "jack_of_trades": ".masteredLectures(5)", "daily_perfect": ".dailyPerfect",
    "power_up_pro": ".allPowerUps",
}
ICONS = {
    "BookOpen": "book", "Target": "target", "Flame": "flame", "Clock": "clock",
    "TrendingUp": "chart.line.uptrend.xyaxis", "Brain": "brain", "Users": "person.2",
    "Calendar": "calendar", "Sparkles": "sparkles", "Trophy": "trophy", "Star": "star",
    "Award": "rosette", "Zap": "bolt", "Crown": "crown", "Medal": "medal", "Sun": "sun.max",
    "Moon": "moon", "Coffee": "cup.and.saucer", "Heart": "heart", "Rocket": "paperplane",
    "GraduationCap": "graduationcap", "Lightbulb": "lightbulb", "CheckCircle": "checkmark.circle",
    "CheckCircle2": "checkmark.circle.fill", "Gem": "diamond", "Shield": "shield",
    "Mountain": "mountain.2", "Sunrise": "sunrise", "Sunset": "sunset", "Library": "books.vertical",
    "UserPlus": "person.badge.plus", "Upload": "square.and.arrow.up", "Layers": "square.stack.3d.up",
    "Infinity": "infinity", "Timer": "timer", "RefreshCw": "arrow.clockwise", "ArrowUp": "arrow.up",
    "Repeat": "repeat", "Swords": "figure.fencing", "Compass": "safari", "Gauge": "gauge",
    "CalendarDays": "calendar", "CalendarCheck": "calendar.badge.checkmark",
    "CalendarRange": "calendar.day.timeline.left", "Palette": "paintpalette", "Mail": "envelope",
    "Handshake": "hands.clap", "LineChart": "chart.xyaxis.line", "Focus": "scope",
    "BarChart3": "chart.bar", "Wand2": "wand.and.stars",
}
CATS = {"study_milestones": "studyMilestones", "perfect_scores": "perfectScores",
        "streak_masters": "streakMasters", "time_based": "timeBased", "improvement": "improvement",
        "topic_mastery": "topicMastery", "social": "social", "daily_quiz": "dailyQuiz",
        "special": "special"}


def rule(aid: str) -> str:
    if aid in SPECIAL:
        return SPECIAL[aid]
    expr = rules.get(aid, "")
    for pat, fmt in PATTERNS:
        m = re.match(pat, expr)
        if m:
            return fmt.format(m.group(1))
    return ".webOnly"  # friends, leaderboard, calendar: features of the hosted web app


def q(x: str) -> str:
    return '"' + x.replace("\\", "\\\\").replace('"', '\\"') + '"'


lines = [
    f"        AchievementDef(id: {q(i)}, name: {q(n)}, detail: {q(d)}, symbol: {q(ICONS.get(ic, 'star'))}, "
    f"category: .{CATS[c]}, xpReward: {xp}, maxProgress: {mx}, rule: {rule(i)}),"
    for i, n, d, ic, c, xp, mx in objs
]
OUT.write_text(
    "// AUTO-GENERATED from shared/schema.ts (ALL_ACHIEVEMENTS) and client/src/lib/game-utils.ts.\n"
    "// Keeps the Mac app's achievements identical to the web app's.\n"
    "// Regenerate with: python3 macos/scripts/generate_achievements.py\n\n"
    "enum AchievementCatalog {\n    static let all: [AchievementDef] = [\n"
    + "\n".join(lines) + "\n    ]\n}\n")
print(f"wrote {len(lines)} achievements -> {OUT.relative_to(ROOT)}")
