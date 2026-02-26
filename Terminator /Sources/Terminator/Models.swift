import Foundation

struct HotkeyConfig: Codable, Equatable {
    var keyCode: UInt16
    var modifiersRaw: UInt

    static let `default` = HotkeyConfig(
        keyCode: 49, // space
        modifiersRaw: UInt((1 << 20) | (1 << 19)) // command + option
    )
}

enum Provider: String, CaseIterable, Codable, Identifiable {
    case openai
    case anthropic
    case gemini
    case openrouter
    case openrouterFree

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .gemini: return "Gemini"
        case .openrouter: return "OpenRouter"
        case .openrouterFree: return "OpenRouter Free"
        }
    }
}

struct ModelOption: Codable, Identifiable, Hashable {
    let provider: Provider
    let modelID: String
    let displayName: String

    var id: String { "\(provider.rawValue)::\(modelID)" }
    var menuLabel: String { "\(provider.title) - \(displayName)" }
}

struct ProviderKeys: Codable {
    var openAI: String = ""
    var anthropic: String = ""
    var gemini: String = ""
    var openRouter: String = ""
}

struct CustomProvider: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var urlString: String
    var isEnabled: Bool

    init(id: UUID = UUID(), name: String, urlString: String, isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.urlString = urlString
        self.isEnabled = isEnabled
    }
}

struct ChatMessage: Codable, Identifiable {
    enum Role: String, Codable {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    let text: String
    let createdAt: Date

    init(id: UUID = UUID(), role: Role, text: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}

struct ChatSession: Codable, Identifiable {
    let id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var messages: [ChatMessage]

    init(
        id: UUID = UUID(),
        title: String = "New Chat",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        messages: [ChatMessage] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
    }
}

struct PersistedState: Codable {
    var keys: ProviderKeys = ProviderKeys()
    var selectedModelID: String? = nil
    var messages: [ChatMessage] = []
    var sessions: [ChatSession]? = nil
    var currentSessionID: UUID? = nil
    var prefersNativeTab: Bool = true
    var prefersDocsumoTab: Bool = true
    var showUnconfiguredProviders: Bool = false
    var panelHotkeyEnabled: Bool = true
    var panelHotkey: HotkeyConfig = .default
    var panelWidth: Double = 630
    var panelHeight: Double = 620
    var webZoom: Double = 1.0
    var favoriteModelIDs: [String] = []
    var customProviders: [CustomProvider]? = nil
}

struct AttachmentItem: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let name: String

    init(id: UUID = UUID(), url: URL) {
        self.id = id
        self.url = url
        self.name = url.lastPathComponent
    }
}
