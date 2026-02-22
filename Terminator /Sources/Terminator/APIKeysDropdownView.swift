import SwiftUI

struct APIKeysDropdownView: View {
    @ObservedObject var state: AppState
    let onOpenFullSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("API Keys")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))

            keyField("OpenAI", text: $state.keys.openAI)
            keyField("Anthropic", text: $state.keys.anthropic)
            keyField("Gemini", text: $state.keys.gemini)
            keyField("OpenRouter", text: $state.keys.openRouter)

            Text("OpenRouter free models work without a key.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))

            HStack(spacing: 8) {
                Button("Save + Load Models") {
                    state.saveKeysAndRefresh()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Open Full Settings") {
                    onOpenFullSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(width: 360)
        .background(Color(red: 0.08, green: 0.09, blue: 0.11))
    }

    private func keyField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))

            SecureField("Enter \(label) key", text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
