import SwiftUI

struct AchievementsView: View {
    @Environment(AppStore.self) private var store
    @State private var filter: AchievementCategory?

    var body: some View {
        let snap = GameEngine.Snapshot(profile: store.profile, lectures: store.lectures, topics: store.topicStats)
        let unlocked = store.profile.unlockedAchievements
        let shown = AchievementCatalog.all.filter { filter == nil || $0.category == filter }
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: "Achievements",
                           subtitle: "\(unlocked.count) of \(AchievementCatalog.all.count) unlocked")
                ProgressView(value: Double(unlocked.count), total: Double(AchievementCatalog.all.count)).tint(Theme.gold)

                Picker("Category", selection: $filter) {
                    Text("All").tag(AchievementCategory?.none)
                    ForEach(AchievementCategory.allCases, id: \.self) { c in
                        Label(c.title, systemImage: c.symbol).tag(AchievementCategory?.some(c))
                    }
                }
                .pickerStyle(.menu).frame(maxWidth: 280)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], spacing: 12) {
                    ForEach(shown) { a in
                        let date = unlocked[a.id]
                        let prog = date != nil ? a.maxProgress : GameEngine.progress(of: a, in: snap)
                        AchievementTile(def: a, unlockedAt: date, progress: prog)
                    }
                }
            }
            .padding(32)
        }
    }
}

struct AchievementTile: View {
    var def: AchievementDef
    var unlockedAt: Date?
    var progress: Int

    var body: some View {
        let done = unlockedAt != nil
        let webOnly = def.rule == .webOnly
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: def.symbol)
                    .font(.title2)
                    .foregroundStyle(done ? Theme.gold : .secondary)
                    .frame(width: 34, height: 34)
                    .background((done ? Theme.gold : Color.secondary).opacity(0.12), in: Circle())
                Spacer()
                Text("+\(def.xpReward) XP").font(.caption.weight(.semibold)).foregroundStyle(done ? Theme.gold : .secondary)
            }
            Text(def.name).font(.headline)
            Text(def.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let unlockedAt {
                Text("Unlocked \(unlockedAt.formatted(date: .abbreviated, time: .omitted))").font(.caption2).foregroundStyle(Theme.gold)
            } else if webOnly {
                Text("Web app only (friends, leaderboard, calendar)").font(.caption2).foregroundStyle(.tertiary)
            } else if def.maxProgress > 1 {
                ProgressView(value: Double(progress), total: Double(def.maxProgress)).tint(Theme.forest)
                Text("\(progress.formatted()) / \(def.maxProgress.formatted())").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .opacity(done ? 1 : 0.75)
    }
}
