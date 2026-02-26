import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: AppState
    @State private var customProviderName: String = ""
    @State private var customProviderURL: String = ""
    @State private var customProviderError: String?

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

            Toggle("Enable Docsumo tab", isOn: Binding(
                get: { state.prefersDocsumoTab },
                set: { newValue in
                    state.prefersDocsumoTab = newValue
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

            Text("Custom Providers")
                .font(.title3.weight(.semibold))

            HStack(spacing: 8) {
                TextField("Name (e.g. Ollama)", text: $customProviderName)
                    .textFieldStyle(.roundedBorder)
                TextField("URL (e.g. http://localhost:11434)", text: $customProviderURL)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    addCustomProvider()
                }
                .buttonStyle(.borderedProminent)
            }

            if let customProviderError {
                Text(customProviderError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if state.customProviders.isEmpty {
                Text("No custom providers added.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(state.customProviders) { provider in
                        HStack(spacing: 10) {
                            Toggle("", isOn: Binding(
                                get: { provider.isEnabled },
                                set: { newValue in
                                    state.setCustomProviderEnabled(id: provider.id, isEnabled: newValue)
                                }
                            ))
                            .toggleStyle(.switch)
                            .labelsHidden()

                            VStack(alignment: .leading, spacing: 2) {
                                Text(provider.name)
                                    .font(.subheadline.weight(.semibold))
                                Text(provider.urlString)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Remove") {
                                state.removeCustomProvider(id: provider.id)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }

            Divider()

            Text("Panel Hotkey")
                .font(.title3.weight(.semibold))
            Text("Global shortcut is fixed to `⌘⇧K`.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("API keys are managed from the Local tab key popup.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 520)
    }

    private func addCustomProvider() {
        customProviderError = state.addCustomProvider(
            name: customProviderName,
            urlString: customProviderURL
        )
        guard customProviderError == nil else { return }
        customProviderName = ""
        customProviderURL = ""
    }
}
