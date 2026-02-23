import SwiftUI

struct ModelDropdownView: View {
    let models: [ModelOption]
    let selectedModelID: String?
    let favoriteModelIDs: Set<String>
    let onSelect: (String) -> Void
    let onToggleFavorite: (String) -> Void
    let onConfigure: () -> Void

    @State private var query: String = ""
    @State private var hoveredModelID: String?
    @FocusState private var searchFocused: Bool

    private var hasQuery: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var filtered: [ModelOption] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return models }
        return models.filter { model in
            model.displayName.lowercased().contains(q) ||
            model.provider.title.lowercased().contains(q) ||
            model.modelID.lowercased().contains(q)
        }
    }

    private var favorites: [ModelOption] {
        filtered.filter { favoriteModelIDs.contains($0.id) }
    }

    private var recommended: [ModelOption] {
        filtered.filter { model in
            let value = model.displayName.lowercased()
            return value.contains("sonnet") || value.contains("gpt") || value.contains("gemini") || value.contains("free")
        }
        .filter { !favoriteModelIDs.contains($0.id) }
        .prefix(8).map { $0 }
    }

    private var others: [ModelOption] {
        let used = Set(favorites.map(\.id) + recommended.map(\.id))
        return filtered.filter { !used.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Select a model...", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if hasQuery {
                        section("Results (\(filtered.count))", items: filtered)
                    } else {
                        section("Favorites", items: favorites)
                        section("Recommended", items: recommended)
                        section("All Models", items: others)
                    }
                }
                .padding(.bottom, 6)
            }

            Divider().overlay(.white.opacity(0.15))

            Button("Configure") {
                onConfigure()
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .frame(width: 420, height: 420)
        .background(Color(red: 0.08, green: 0.09, blue: 0.11))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                searchFocused = true
            }
        }
    }

    private func section(_ title: String, items: [ModelOption]) -> some View {
        Group {
            if !items.isEmpty {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.blue.opacity(0.85))

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(items) { model in
                        HStack(spacing: 8) {
                            Image(systemName: icon(for: model.provider))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.indigo.opacity(0.9))
                                .frame(width: 16)

                            Text(model.displayName)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if selectedModelID == model.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.white.opacity(0.95))
                            }

                            if hoveredModelID == model.id || favoriteModelIDs.contains(model.id) {
                                Button {
                                    onToggleFavorite(model.id)
                                } label: {
                                    Image(systemName: favoriteModelIDs.contains(model.id) ? "star.fill" : "star")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(favoriteModelIDs.contains(model.id) ? .white.opacity(0.95) : .white.opacity(0.7))
                                        .frame(width: 18, height: 18)
                                }
                                .buttonStyle(.plain)
                                .help(favoriteModelIDs.contains(model.id) ? "Remove from favorites" : "Add to favorites")
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                        .background(selectedModelID == model.id ? Color.blue.opacity(0.45) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .onTapGesture {
                            onSelect(model.id)
                        }
                        .onHover { hovering in
                            hoveredModelID = hovering ? model.id : (hoveredModelID == model.id ? nil : hoveredModelID)
                        }
                    }
                }
            }
        }
    }

    private func icon(for provider: Provider) -> String {
        switch provider {
        case .openai: return "sparkle"
        case .anthropic: return "a.circle"
        case .gemini: return "g.circle"
        case .openrouter, .openrouterFree: return "point.3.connected.trianglepath.dotted"
        }
    }
}
