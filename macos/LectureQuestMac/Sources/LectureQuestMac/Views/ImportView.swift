import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @Environment(AppStore.self) private var store
    var done: () -> Void

    @State private var pickingFiles = false
    @State private var dropTargeted = false
    @State private var pasteTitle = ""
    @State private var pasteText = ""
    @State private var generateNow = true
    @State private var jobs: [Job] = []

    struct Job: Identifiable {
        let id = UUID()
        var name: String
        var status: Status
        enum Status: Equatable { case reading, generating, done, failed(String) }
    }

    var running: Bool { jobs.contains { $0.status == .reading || $0.status == .generating } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(title: "Add Lectures", subtitle: "PDF, text or Markdown — up to 20 at a time. Claude writes a 10-question quiz for each.")

                VStack(spacing: 10) {
                    Image(systemName: "doc.badge.plus").font(.system(size: 40)).foregroundStyle(Theme.forest)
                    Text("Drop lecture files here").font(Theme.serif(20))
                    Button("Choose Files…") { pickingFiles = true }.disabled(running)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
                .background(dropTargeted ? Theme.lavender.opacity(0.4) : Color.secondary.opacity(0.05),
                            in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                    .foregroundStyle(.secondary.opacity(0.5)))
                .dropDestination(for: URL.self) { urls, _ in
                    Task { await importFiles(urls) }
                    return true
                } isTargeted: { dropTargeted = $0 }

                Toggle("Generate quizzes right away (uses your Anthropic API key)", isOn: $generateNow)
                    .disabled(!store.hasAPIKey)

                if !jobs.isEmpty {
                    Card {
                        ForEach(jobs) { j in
                            HStack {
                                Text(j.name).lineLimit(1)
                                Spacer()
                                switch j.status {
                                case .reading: Text("Reading…").foregroundStyle(.secondary)
                                case .generating: HStack { ProgressView().controlSize(.small); Text("Writing quiz…") }
                                case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
                                case let .failed(msg): Text(msg).foregroundStyle(.red).font(.caption).lineLimit(2)
                                }
                            }
                        }
                        if !running {
                            Button("View lectures", action: done).buttonStyle(.borderedProminent)
                        }
                    }
                }

                Card {
                    Text("Or paste lecture notes").font(Theme.serif(20))
                    TextField("Title", text: $pasteTitle).textFieldStyle(.roundedBorder)
                    TextEditor(text: $pasteText)
                        .font(.body)
                        .frame(minHeight: 180)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    HStack {
                        Text("\(pasteText.count) characters").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Add Lecture") {
                            let title = pasteTitle, text = pasteText
                            pasteTitle = ""; pasteText = ""
                            Task { await importText(title: title, text: text) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(pasteText.trimmingCharacters(in: .whitespacesAndNewlines).count < 50 || running)
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
        .fileImporter(isPresented: $pickingFiles, allowedContentTypes: DocumentReader.supportedTypes,
                      allowsMultipleSelection: true) { result in
            if case let .success(urls) = result { Task { await importFiles(urls) } }
        }
    }

    private func importFiles(_ urls: [URL]) async {
        let batch = Array(urls.prefix(20))
        var added = 0
        for url in batch {
            let job = Job(name: url.lastPathComponent, status: .reading)
            jobs.append(job)
            do {
                let (title, text) = try DocumentReader.read(url)
                let lecture = store.addLecture(title: title, content: text)
                added += 1
                await generate(lecture.id, job: job.id)
            } catch {
                set(job.id, .failed(error.localizedDescription))
            }
        }
        if added > 1 { store.recordBatchImport(count: added) }
    }

    private func importText(title: String, text: String) async {
        let job = Job(name: title.isEmpty ? "Pasted notes" : title, status: .reading)
        jobs.append(job)
        let lecture = store.addLecture(title: title, content: text)
        await generate(lecture.id, job: job.id)
    }

    private func generate(_ id: UUID, job: UUID) async {
        guard generateNow && store.hasAPIKey else { set(job, .done); return }
        set(job, .generating)
        do {
            try await store.generateQuiz(for: id)
            set(job, .done)
        } catch {
            set(job, .failed(error.localizedDescription))
        }
    }

    private func set(_ id: UUID, _ status: Job.Status) {
        if let i = jobs.firstIndex(where: { $0.id == id }) { jobs[i].status = status }
    }
}
