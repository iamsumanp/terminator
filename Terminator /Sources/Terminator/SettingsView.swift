import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: AppState

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
}
