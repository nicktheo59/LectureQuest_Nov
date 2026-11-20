# LectureQuest for macOS (Swift)

A native SwiftUI port of LectureQuest that runs **entirely on your Mac** — no server, no database,
no sign-in. Your lectures and progress are stored in
`~/Library/Application Support/LectureQuest/data.json`; your Anthropic API key lives in the macOS Keychain.

**What's included (same rules as the web app):**
- Import lectures: drag-and-drop or pick up to 20 PDF / `.txt` / `.md` files, or paste notes
- Claude-generated 10-question quizzes + transferable-skills mapping (same prompts as `server/routes.ts`)
- XP, levels and titles, streaks with 1.5×/2× multipliers, confidence-rating bonus
- Power-ups: Hint (removes two wrong answers), Second Chance (retry once), Double XP
- SM-2 spaced repetition per topic and a prioritised **Daily Review** active-recall quiz
- Skills profile with CSV export
- All 100 achievements (generated from `shared/schema.ts`; friends/leaderboard/calendar ones are marked web-only)
- Keyboard: `1`–`4` choose an answer, `Return` checks / advances, `Esc` quits, `⌘,` Settings

## Requirements
- macOS 14 Sonoma or later
- Xcode 15+ (or just the Command Line Tools: `xcode-select --install`)
- An Anthropic API key — <https://console.anthropic.com/settings/keys>

## Run it

```bash
cd macos/LectureQuestMac
swift run                    # builds and launches the app
```

Then press **⌘,** → paste your API key → **Save key**.

### Or open in Xcode
```bash
open macos/LectureQuestMac/Package.swift
```
Pick the **LectureQuest** scheme → *My Mac* → ▶︎ Run (⌘R).

### Build a real .app for your Applications folder
```bash
cd macos/LectureQuestMac
./scripts/build-app.sh --install    # -> ~/Applications/LectureQuest.app
```
The app is ad-hoc signed for local use. If macOS says it "can't be opened", right-click → **Open** once.

## Tests
```bash
swift test
```

## Project layout
```
Sources/LectureQuestMac/
  LectureQuestApp.swift     app entry + Settings scene
  Models.swift              Codable data model
  GameEngine.swift          XP, levels, SM-2, achievement rules (ported from game-utils.ts)
  AchievementCatalog.swift  generated: `python3 macos/scripts/generate_achievements.py` (from repo root)
  AppStore.swift            state, persistence, quiz scoring
  QuizSession.swift         per-quiz state machine
  ClaudeClient.swift        Anthropic Messages API client
  Keychain.swift / DocumentReader.swift
  Views/                    SwiftUI screens
```
