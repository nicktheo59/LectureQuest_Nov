import SwiftUI
import AppKit

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var key = ""
    @State private var saved = false
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section("Anthropic API") {
                SecureField("API key (sk-ant-…)", text: $key)
                HStack {
                    Button("Save key") {
                        store.setAPIKey(key)
                        saved = true
                    }
                    .disabled(key.isEmpty)
                    if saved { Label("Saved to Keychain", systemImage: "checkmark").foregroundStyle(Theme.success) }
                    Spacer()
                    Link("Get a key", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                }
                TextField("Model", text: Binding(get: { store.model }, set: { store.setModel($0) }))
                Text("Default: \(ClaudeClient.defaultModel). Any Messages-API model id works.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Profile") {
                TextField("Your name", text: Binding(
                    get: { store.profile.displayName },
                    set: { store.setDisplayName($0) }))
            }
            Section("Data") {
                LabeledContent("Stored at") {
                    Button(AppStore.storeURL.path(percentEncoded: false)) {
                        NSWorkspace.shared.activateFileViewerSelecting([AppStore.storeURL])
                    }
                    .buttonStyle(.link)
                }
                Button("Reset all progress…", role: .destructive) { confirmReset = true }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 420)
        .onAppear { key = store.apiKey }
        .confirmationDialog("Reset all LectureQuest data?", isPresented: $confirmReset) {
            Button("Delete everything", role: .destructive) { store.resetAll() }
        } message: {
            Text("Lectures, XP, achievements and review history will be permanently deleted.")
        }
    }
}
