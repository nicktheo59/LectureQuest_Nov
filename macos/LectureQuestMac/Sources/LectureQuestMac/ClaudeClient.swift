import Foundation

enum ClaudeError: LocalizedError {
    case missingAPIKey
    case http(Int, String)
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add your Anthropic API key in Settings (⌘,) to generate quizzes."
        case let .http(code, body):
            switch code {
            case 401: return "Anthropic rejected the API key (401). Check it in Settings."
            case 429: return "Too many requests — wait a moment and try again."
            case 529, 503: return "Claude is overloaded right now. Try again shortly."
            default: return "Claude API error \(code): \(body.prefix(300))"
            }
        case let .badResponse(why):
            return "Couldn't read Claude's response (\(why)). Please try again."
        }
    }
}

/// Minimal Anthropic Messages API client (same prompts as server/routes.ts).
struct ClaudeClient {
    var apiKey: String
    var model: String

    static let defaultModel = "claude-sonnet-4-20250514"

    func complete(_ prompt: String, maxTokens: Int = 4096) async throws -> String {
        guard !apiKey.isEmpty else { throw ClaudeError.missingAPIKey }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": [["role": "user", "content": prompt]],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw ClaudeError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]] else {
            throw ClaudeError.badResponse("unexpected envelope")
        }
        return content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined()
    }

    // MARK: Lecture quiz

    func generateLectureQuiz(content: String) async throws -> (questions: [Question], skills: [Skill]) {
        let prompt = """
        Analyze this lecture content and generate a quiz with transferable skills identification.

        LECTURE CONTENT:
        \(content.prefix(60_000))

        Return ONLY valid JSON in this exact format:
        {
          "questions": [
            {
              "question": "string",
              "options": ["string", "string", "string", "string"],
              "correct": number (0-3),
              "explanation": "string",
              "topic": "string (specific concept being tested)"
            }
          ],
          "skills": [
            {
              "name": "string (e.g. 'Analytical Thinking', 'Problem Solving', 'Systems Design')",
              "description": "string (1 sentence explaining how this lecture develops this skill)",
              "category": "cognitive|technical|communication|interpersonal|organizational",
              "relevantCareers": ["string", "string", "string"]
            }
          ]
        }

        Requirements:
        - Generate exactly 10 questions
        - Each question must have exactly 4 options
        - "correct" must be an index from 0 to 3
        - Questions should test understanding, not just memorization
        - The "topic" field must be a specific, descriptive concept name (not generic words)
        - Identify 3-5 transferable skills that students develop by mastering this content
        - Skills should be career-relevant (e.g., "Critical Analysis", "Data Interpretation", "Logical Reasoning", "Technical Communication")
        - Map each skill to 2-3 relevant career paths
        - DO NOT include any text outside the JSON object
        """
        let raw = try await complete(prompt)
        let obj = try Self.parseJSON(raw)
        let qs = Self.questions(from: (obj as? [String: Any])?["questions"] ?? obj, fallbackTopic: "General Concept")
        guard !qs.isEmpty else { throw ClaudeError.badResponse("no questions") }
        let skills = Self.skills(from: (obj as? [String: Any])?["skills"])
        return (qs, skills)
    }

    // MARK: Daily active-recall quiz

    func generateDailyQuiz(topics: [PlannedTopic], excerpts: [(title: String, excerpt: String)],
                           streak: Int, averageConfidence: Double) async throws -> [Question] {
        let topicList = topics.map { t -> String in
            let tag = t.reason == .overdue ? "(overdue)" : t.reason == .weak ? "(needs practice)" : t.reason == .new ? "(recently learned)" : ""
            return "- \(t.topic) from \"\(t.lectureTitle)\" \(tag)"
        }.joined(separator: "\n")
        let context = excerpts.map { "Lecture: \($0.title)\nContent: \($0.excerpt)" }.joined(separator: "\n\n")
        let prompt = """
        Generate exactly 10 targeted multiple-choice questions using active recall principles for these topics that need review:

        \(topicList)

        Context from the student's lectures:
        \(context)

        Student Progress:
        - Current streak: \(streak) days
        - Average confidence: \(String(format: "%.1f", averageConfidence))/5

        Active Recall Instructions:
        1. Questions should test RETRIEVAL of knowledge, not recognition
        2. Include questions that require connecting concepts across topics
        3. Use varied question formats (application, analysis, comparison)
        4. Focus on the "why" and "how" not just the "what"
        5. Include some questions that require recalling specific details
        6. Base questions on the actual lecture content provided above

        Return ONLY valid JSON in this exact format:
        [
          {
            "question": "string",
            "options": ["string", "string", "string", "string"],
            "correct": number (0-3),
            "explanation": "string",
            "topic": "string (which topic this tests — use one of the topic names above exactly)"
          }
        ]

        Important:
        - Generate exactly 10 questions
        - Each question must have exactly 4 options
        - "correct" must be an index from 0 to 3
        - Explanations should reinforce learning and encourage spaced repetition
        - DO NOT include any text outside the JSON array
        """
        let raw = try await complete(prompt)
        let qs = Self.questions(from: try Self.parseJSON(raw), fallbackTopic: topics.first?.topic ?? "General")
        guard !qs.isEmpty else { throw ClaudeError.badResponse("no questions") }
        return qs
    }

    // MARK: Lenient parsing (mirrors the validation in server/routes.ts)

    static func parseJSON(_ text: String) throws -> Any {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            s = s.replacingOccurrences(of: "^```(?:json)?\\s*", with: "", options: .regularExpression)
            s = s.replacingOccurrences(of: "\\s*```\\s*$", with: "", options: .regularExpression)
        }
        if let start = s.firstIndex(where: { $0 == "{" || $0 == "[" }),
           let end = s.lastIndex(where: { $0 == "}" || $0 == "]" }), start <= end {
            s = String(s[start...end])
        }
        guard let data = s.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) else {
            throw ClaudeError.badResponse("invalid JSON")
        }
        return obj
    }

    static func questions(from any: Any?, fallbackTopic: String) -> [Question] {
        guard let arr = any as? [[String: Any]] else { return [] }
        return arr.enumerated().compactMap { i, q in
            let options = (q["options"] as? [Any])?.map { "\($0)" } ?? []
            guard options.count == 4 else { return nil }
            let correct = (q["correct"] as? Int) ?? Int("\(q["correct"] ?? 0)") ?? 0
            return Question(
                question: (q["question"] as? String) ?? "Question \(i + 1)",
                options: options,
                correct: (0...3).contains(correct) ? correct : 0,
                explanation: (q["explanation"] as? String) ?? "Keep practising — you're making progress.",
                topic: ((q["topic"] as? String)?.trimmingCharacters(in: .whitespaces)).flatMap { $0.isEmpty ? nil : $0 } ?? fallbackTopic
            )
        }
    }

    static func skills(from any: Any?) -> [Skill] {
        guard let arr = any as? [[String: Any]] else { return [] }
        return arr.map { s in
            Skill(
                name: (s["name"] as? String) ?? "General Skill",
                description: (s["description"] as? String) ?? "Developed through this lecture",
                category: SkillCategory(rawValue: (s["category"] as? String) ?? "") ?? .cognitive,
                relevantCareers: Array(((s["relevantCareers"] as? [Any])?.map { "\($0)" } ?? ["Various Industries"]).prefix(5))
            )
        }
    }
}
