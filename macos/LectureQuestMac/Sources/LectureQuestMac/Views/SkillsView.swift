import SwiftUI
import UniformTypeIdentifiers

struct SkillsView: View {
    @Environment(AppStore.self) private var store
    @State private var exporting = false

    var body: some View {
        let skills = store.aggregatedSkills
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    PageHeader(title: "Skills Profile",
                               subtitle: "Transferable skills Claude identified across your lectures, with proficiency from your quiz accuracy.")
                    Button { exporting = true } label: { Label("Export CSV", systemImage: "square.and.arrow.up") }
                        .disabled(skills.isEmpty)
                }

                if skills.isEmpty {
                    ContentUnavailableView("No skills yet", systemImage: "briefcase",
                                           description: Text("Generate a quiz for a lecture to map its transferable skills."))
                } else {
                    HStack(spacing: 12) {
                        ForEach([Proficiency.proficient, .intermediate, .developing], id: \.self) { p in
                            StatPill(symbol: "circle.fill", value: "\(skills.filter { $0.skill.proficiency == p }.count)",
                                     label: p.rawValue.capitalized, tint: p.color)
                        }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)], spacing: 14) {
                        ForEach(skills) { a in
                            Card {
                                HStack {
                                    Text(a.skill.name).font(.headline)
                                    Spacer()
                                    Text(a.skill.proficiency.rawValue.capitalized)
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(a.skill.proficiency.color.opacity(0.15), in: Capsule())
                                        .foregroundStyle(a.skill.proficiency.color)
                                }
                                Text(a.skill.description).font(.callout).foregroundStyle(.secondary)
                                FlowLayout(spacing: 6) {
                                    ForEach(a.skill.relevantCareers, id: \.self) { c in
                                        Text(c).font(.caption)
                                            .padding(.horizontal, 8).padding(.vertical, 3)
                                            .background(Theme.lavender.opacity(0.5), in: Capsule())
                                    }
                                }
                                Text("From: " + a.lectures.joined(separator: ", ")).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
            .padding(32)
        }
        .fileExporter(isPresented: $exporting, document: CSVDocument(text: store.skillsCSV()),
                      contentType: .commaSeparatedText, defaultFilename: "LectureQuest-skills.csv") { _ in }
    }
}

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = configuration.file.regularFileContents.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
