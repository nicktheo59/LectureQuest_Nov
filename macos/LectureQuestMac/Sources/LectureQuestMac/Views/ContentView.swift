import SwiftUI

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case today = "Today", lectures = "Lectures", importer = "Add Lectures", skills = "Skills", achievements = "Achievements"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .today: "sun.max"
        case .lectures: "books.vertical"
        case .importer: "square.and.arrow.down"
        case .skills: "briefcase"
        case .achievements: "trophy"
        }
    }
}

struct ContentView: View {
    @Environment(AppStore.self) private var store
    @State private var section: AppSection? = .today
    @State private var session: QuizSession?

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                ForEach(AppSection.allCases) { s in
                    Label(s.rawValue, systemImage: s.symbol).tag(s as AppSection?)
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .safeAreaInset(edge: .bottom) { SidebarProfile().padding(12) }
        } detail: {
            Group {
                switch section ?? .today {
                case .today: TodayView(startQuiz: { session = $0 }, goTo: { section = $0 })
                case .lectures: LecturesView(startQuiz: { session = $0 }, goTo: { section = $0 })
                case .importer: ImportView(done: { section = .lectures })
                case .skills: SkillsView()
                case .achievements: AchievementsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(item: $session) { s in
            QuizView(session: s, close: { session = nil })
                .environment(store)
                .frame(minWidth: 720, idealWidth: 780, minHeight: 600, idealHeight: 680)
        }
        .overlay(alignment: .topTrailing) { AchievementToastStack() }
        .alert("Something went wrong", isPresented: Binding(
            get: { store.lastError != nil }, set: { if !$0 { store.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.lastError ?? "")
        }
    }
}

struct SidebarProfile: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        let p = store.profile
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Level \(p.level)").font(.headline)
                Spacer()
                if p.currentStreak > 0 {
                    Label("\(p.currentStreak)", systemImage: "flame.fill").foregroundStyle(Theme.gold).font(.subheadline)
                }
            }
            Text(GameEngine.levelTitle(p.level)).font(.caption).foregroundStyle(.secondary)
            ProgressView(value: GameEngine.levelProgress(xp: p.totalXP)).tint(Theme.forest)
            Text("\(p.totalXP) XP · \(GameEngine.xpForNextLevel(p.level) - p.totalXP) to next")
                .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct AchievementToastStack: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(Array(store.toastAchievements.prefix(3).enumerated()), id: \.element.id) { _, a in
                HStack(spacing: 10) {
                    Image(systemName: a.symbol).font(.title2).foregroundStyle(Theme.gold)
                    VStack(alignment: .leading) {
                        Text("Achievement unlocked").font(.caption).foregroundStyle(.secondary)
                        Text(a.name).font(.headline)
                    }
                    Text("+\(a.xpReward) XP").font(.caption.weight(.semibold)).foregroundStyle(Theme.gold)
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 8, y: 2)
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .task {
                    try? await Task.sleep(for: .seconds(3.5))
                    withAnimation { store.toastAchievements.removeAll { $0.id == a.id } }
                }
            }
        }
        .padding(16)
        .animation(.spring, value: store.toastAchievements.map(\.id))
    }
}
