# LectureQuest for macOS

A small, offline-native companion to the LectureQuest web app. This directory is a standalone Swift Package; it does not need the rest of the repository, Node, a server, an account, or any secrets.

## Run locally

On macOS 14 or later with Swift 5.9+ and the macOS SDK (Xcode 15+ or its Command Line Tools), run this from the repository root:

```sh
cd macos
swift run LectureQuest
```

Or open `Package.swift` in Xcode, select the **LectureQuest** scheme and **My Mac**, and run it. This is a SwiftPM executable for local use, not a signed `.app` or installer. If you are running a copy of only this directory, run `swift run LectureQuest` directly inside it.

## Study workflow

1. **Import Material** (⌘O) copies one PDF or plain-text file into a new lecture. PDFKit displays PDFs; text and Markdown are shown as plain, selectable text. Use **New Lecture** (⌘N) to start without a file.
2. Open **Notes** to write or edit notes. Changes save automatically; a failed write leaves the current draft available in memory to retry. Leaving the app while a draft is still unsaved discards that draft.
3. In **Flashcards**, create your own question-and-answer cards. Use the card’s menu to edit or delete it. Editing preserves prior review progress.
4. Choose **Practice → Due Cards** or **All Cards**. Reveal each answer, then choose **Again** (`1`, due in 10 minutes) or **Got It** (`2`, starts at one day, doubles up to 30 days). A new card is immediately due. Both practice modes update the schedule and save each rating as you go. A card appears once per session; if you end early, completed ratings remain saved.

Your library lives at `~/Library/Application Support/LectureQuest/`: `library.json` holds notes, decks, and review history fields (count, last reviewed, and next due), and `Materials/` holds copies of imports. The app writes the index atomically. Quit the app before backing up or restoring the whole folder, and run one instance at a time. Removing a lecture removes its local study data and copy, not the original file. If a library cannot be read, the app reports the error without replacing it.

## Scope and limitations

- PDF up to 64 MiB; UTF-8 or BOM-marked UTF-16 text up to 2 MiB. No OCR, PDF annotation, encrypted PDFs, rich-text/Office import, or rendered Markdown. One imported file per lecture; no reattachment or replacement in this edition.
- No Google sign-in or Drive, cloud sync, Claude or other AI features, automatic card generation, daily quizzes, XP, calendar integration, or compatibility/migration with the React app’s data. No reminders, per-rating event log, or sync between Macs. An interrupted practice session itself is not resumed.
- No installer, code signing, or third-party libraries.

## Verify on a Mac

```sh
swift build
swift test
swift run LectureQuest
```

For a UI smoke test, create a blank lecture and import one PDF and one text file. Switch between lectures, add notes and a flashcard, rate it in **Due Cards**, quit, and relaunch. Verify that materials and notes reopen, the review count and next review date remain, the newly rated card is absent from **Due Cards** until its due time, and it is still available under **All Cards**. Rename and delete a lecture and confirm its original import file still exists.
