import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: AppState
    @State private var revealedProviders: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Interface")
                .font(.title3.weight(.semibold))

            Toggle("Enable native Local tab", isOn: Binding(
                get: { state.prefersNativeTab },
                set: { newValue in
                    state.prefersNativeTab = newValue
                    state.persist()
                }
            ))

            Toggle("Show providers without API keys", isOn: Binding(
                get: { state.showUnconfiguredProviders },
                set: { newValue in
                    state.showUnconfiguredProviders = newValue
                    state.persist()
                }
            ))

            Divider()

            Text("Panel Hotkey")
                .font(.title3.weight(.semibold))
            Text("Global shortcut is fixed to `⌘⇧K`.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            Text("Provider API Keys")
                .font(.title3.weight(.semibold))

            providerRow("OpenAI", text: $state.keys.openAI)
            providerRow("Anthropic", text: $state.keys.anthropic)
            providerRow("Gemini", text: $state.keys.gemini)
            providerRow("OpenRouter", text: $state.keys.openRouter)

            Text("OpenRouter free models are fetched automatically even without any key.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Save and Load Models") {
                    state.saveKeysAndRefresh()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func keyField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.subheadline.weight(.medium))
            SecureField("Enter \(label) API key", text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    @ViewBuilder
    private func providerRow(_ label: String, text: Binding<String>) -> some View {
        let hasKey = !text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let shouldShow = state.showUnconfiguredProviders || hasKey || revealedProviders.contains(label)

        if shouldShow {
            keyField(label, text: text)
        } else {
            HStack {
                Text("\(label) hidden (no key)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Add") {
                    revealedProviders.insert(label)
                }
            }
        }
    }
}
