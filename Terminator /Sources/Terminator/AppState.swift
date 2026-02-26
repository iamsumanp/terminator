import Foundation
import SwiftUI
import AppKit

@MainActor
final class AppState: ObservableObject {
    @Published var keys: ProviderKeys
    @Published var availableModels: [ModelOption] = []
    @Published var selectedModelID: String?
    @Published var messages: [ChatMessage]
    @Published var sessions: [ChatSession]
    @Published var currentSessionID: UUID
    @Published var draft: String = ""
    @Published var isLoadingModels: Bool = false
    @Published var isSending: Bool = false
    @Published var errorMessage: String?
    @Published var showingSettings: Bool = false
    @Published var attachments: [AttachmentItem] = []
    @Published var prefersNativeTab: Bool
    @Published var prefersDocsumoTab: Bool
    @Published var showUnconfiguredProviders: Bool
    @Published var panelHotkeyEnabled: Bool
    @Published var panelHotkey: HotkeyConfig
    @Published var panelWidth: Double
    @Published var panelHeight: Double
    @Published var webZoom: Double
    @Published var favoriteModelIDs: [String]
    @Published var customProviders: [CustomProvider]
    @Published var focusRequestToken: Int = 0

    private let api = APIService()

    init() {
        let loaded = Persistence.loadState()
        self.keys = loaded.keys
        self.selectedModelID = loaded.selectedModelID
        self.prefersNativeTab = loaded.prefersNativeTab
        self.prefersDocsumoTab = loaded.prefersDocsumoTab
        self.showUnconfiguredProviders = loaded.showUnconfiguredProviders
        self.panelHotkeyEnabled = loaded.panelHotkeyEnabled
        self.panelHotkey = loaded.panelHotkey
        self.panelWidth = loaded.panelWidth
        self.panelHeight = loaded.panelHeight
        self.webZoom = loaded.webZoom
        self.favoriteModelIDs = loaded.favoriteModelIDs
        self.customProviders = loaded.customProviders ?? []

        if let savedSessions = loaded.sessions, !savedSessions.isEmpty {
            let fallbackID = savedSessions[0].id
            let selectedID = loaded.currentSessionID ?? fallbackID
            let currentID = savedSessions.contains(where: { $0.id == selectedID }) ? selectedID : fallbackID
            self.sessions = savedSessions
            self.currentSessionID = currentID
            self.messages = savedSessions.first(where: { $0.id == currentID })?.messages ?? []
        } else {
            let initial = ChatSession(
                title: loaded.messages.first(where: { $0.role == .user }).map { Self.sessionTitle(from: $0.text) } ?? "New Chat",
                messages: loaded.messages
            )
            self.sessions = [initial]
            self.currentSessionID = initial.id
            self.messages = initial.messages
        }
    }

    var selectedModel: ModelOption? {
        availableModels.first(where: { $0.id == selectedModelID })
    }

    func requestInputFocus() {
        focusRequestToken &+= 1
    }

    func boot() {
        Task {
            await refreshModels()
        }
    }

    func refreshModels() async {
        isLoadingModels = true
        let fetched = await api.fetchModels(keys: keys)
        availableModels = fetched

        if selectedModel == nil {
            selectedModelID = fetched.first?.id
        }

        isLoadingModels = false
        persist()
    }

    func persist() {
        syncCurrentSession()
        Persistence.saveState(
            PersistedState(
                keys: keys,
                selectedModelID: selectedModelID,
                messages: messages,
                sessions: sessions,
                currentSessionID: currentSessionID,
                prefersNativeTab: prefersNativeTab,
                prefersDocsumoTab: prefersDocsumoTab,
                showUnconfiguredProviders: showUnconfiguredProviders,
                panelHotkeyEnabled: panelHotkeyEnabled,
                panelHotkey: panelHotkey,
                panelWidth: panelWidth,
                panelHeight: panelHeight,
                webZoom: webZoom,
                favoriteModelIDs: favoriteModelIDs,
                customProviders: customProviders
            )
        )
    }

    @discardableResult
    func addCustomProvider(name: String, urlString: String) -> String? {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty else { return "Provider name is required." }

        guard let normalizedURL = normalizeProviderURL(urlString) else {
            return "Enter a valid URL, for example https://ollama.com."
        }

        let normalizedText = normalizedURL.absoluteString.lowercased()
        if customProviders.contains(where: { normalizeProviderURL($0.urlString)?.absoluteString.lowercased() == normalizedText }) {
            return "That provider URL already exists."
        }

        customProviders.append(CustomProvider(name: cleanedName, urlString: normalizedURL.absoluteString))
        persist()
        return nil
    }

    func removeCustomProvider(id: UUID) {
        customProviders.removeAll { $0.id == id }
        persist()
    }

    func setCustomProviderEnabled(id: UUID, isEnabled: Bool) {
        guard let index = customProviders.firstIndex(where: { $0.id == id }) else { return }
        customProviders[index].isEnabled = isEnabled
        persist()
    }

    func normalizedCustomProviderURL(_ provider: CustomProvider) -> URL? {
        normalizeProviderURL(provider.urlString)
    }

    func clearChat() {
        createNewSession()
        persist()
    }

    func createNewSession() {
        let session = ChatSession()
        sessions.insert(session, at: 0)
        currentSessionID = session.id
        messages = []
        attachments.removeAll()
        draft = ""
        errorMessage = nil
    }

    func selectSession(_ id: UUID) {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        currentSessionID = session.id
        messages = session.messages
        attachments.removeAll()
        errorMessage = nil
    }

    func saveKeysAndRefresh() {
        persist()
        Task {
            await refreshModels()
        }
    }

    func toggleFavoriteModel(_ id: String) {
        if favoriteModelIDs.contains(id) {
            favoriteModelIDs.removeAll { $0 == id }
        } else {
            favoriteModelIDs.append(id)
        }
        persist()
    }

    func sendCurrentDraft() {
        let text = composePromptWithAttachments()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard let selectedModel else {
            errorMessage = "Select a model first. You can also use OpenRouter free models without an API key."
            return
        }

        let priorHistory = messages
        let priorAttachments = attachments
        draft = ""
        attachments.removeAll()
        messages.append(ChatMessage(role: .user, text: text))
        updateSessionTitleIfNeeded(using: text)
        errorMessage = nil
        persist()

        Task {
            isSending = true
            do {
                let reply = try await api.send(
                    message: text,
                    to: selectedModel,
                    keys: keys,
                    history: priorHistory,
                    attachments: priorAttachments
                )
                messages.append(ChatMessage(role: .assistant, text: reply))
                persist()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSending = false
        }
    }

    func pickAttachments() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true
        panel.title = "Attach files"
        panel.prompt = "Attach"

        if panel.runModal() == .OK {
            let newItems = panel.urls.map { AttachmentItem(url: $0) }
            attachments.append(contentsOf: newItems)
            attachments = dedupeAttachments(attachments)
        }
    }

    func removeAttachment(_ id: UUID) {
        attachments.removeAll { $0.id == id }
    }

    private func composePromptWithAttachments() -> String {
        guard !attachments.isEmpty else { return draft }

        let header = "\n\nAttached files:\n" + attachments.map { "- \($0.name)" }.joined(separator: "\n")
        let extracted = attachments.compactMap(readTextAttachment).joined(separator: "\n\n")

        if extracted.isEmpty {
            return draft + header
        }
        return draft + header + "\n\nExtracted text:\n" + extracted
    }

    private func readTextAttachment(_ item: AttachmentItem) -> String? {
        do {
            let values = try item.url.resourceValues(forKeys: [.fileSizeKey])
            if let fileSize = values.fileSize, fileSize > 200_000 {
                return nil
            }
            let text = try String(contentsOf: item.url, encoding: .utf8)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return "File: \(item.name)\n\(trimmed.prefix(4000))"
        } catch {
            return nil
        }
    }

    private func dedupeAttachments(_ list: [AttachmentItem]) -> [AttachmentItem] {
        var seen = Set<String>()
        var output: [AttachmentItem] = []
        for item in list {
            let path = item.url.standardizedFileURL.path
            if !seen.contains(path) {
                seen.insert(path)
                output.append(item)
            }
        }
        return output
    }

    private func syncCurrentSession() {
        guard let index = sessions.firstIndex(where: { $0.id == currentSessionID }) else {
            return
        }
        sessions[index].messages = messages
        sessions[index].updatedAt = Date()
    }

    private func updateSessionTitleIfNeeded(using prompt: String) {
        guard let index = sessions.firstIndex(where: { $0.id == currentSessionID }) else { return }
        if sessions[index].title == "New Chat" || sessions[index].title.trimmingCharacters(in: .whitespaces).isEmpty {
            sessions[index].title = Self.sessionTitle(from: prompt)
        }
        sessions[index].updatedAt = Date()
    }

    var sortedSessions: [ChatSession] {
        sessions.sorted { $0.updatedAt > $1.updatedAt }
    }

    var currentSessionTitle: String {
        sessions.first(where: { $0.id == currentSessionID })?.title ?? "New Chat"
    }

    private static func sessionTitle(from text: String) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return "New Chat" }
        return String(cleaned.prefix(42))
    }

    private func normalizeProviderURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let withScheme: String
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            withScheme = trimmed
        } else {
            withScheme = "https://\(trimmed)"
        }

        guard let url = URL(string: withScheme),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host != nil else {
            return nil
        }
        return url
    }
}
