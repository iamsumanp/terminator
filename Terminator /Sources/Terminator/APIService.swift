import Foundation

struct APIService {
    private let session: URLSession = .shared

    func fetchModels(keys: ProviderKeys) async -> [ModelOption] {
        await withTaskGroup(of: [ModelOption].self) { group in
            group.addTask { await self.fetchOpenRouterFreeModels() }

            if !keys.openAI.isEmpty {
                group.addTask { await self.fetchOpenAIModels(apiKey: keys.openAI) }
            }
            if !keys.anthropic.isEmpty {
                group.addTask { await self.fetchAnthropicModels(apiKey: keys.anthropic) }
            }
            if !keys.gemini.isEmpty {
                group.addTask { await self.fetchGeminiModels(apiKey: keys.gemini) }
            }
            if !keys.openRouter.isEmpty {
                group.addTask { await self.fetchOpenRouterModels(apiKey: keys.openRouter) }
            }

            var merged: [ModelOption] = []
            for await chunk in group {
                merged.append(contentsOf: chunk)
            }
            return merged.sorted { $0.menuLabel.localizedCaseInsensitiveCompare($1.menuLabel) == .orderedAscending }
        }
    }

    func send(
        message: String,
        to model: ModelOption,
        keys: ProviderKeys,
        history: [ChatMessage],
        attachments: [AttachmentItem]
    ) async throws -> String {
        switch model.provider {
        case .openai:
            return try await sendOpenAI(
                message: message,
                modelID: model.modelID,
                apiKey: keys.openAI,
                history: history,
                attachments: attachments
            )
        case .anthropic:
            return try await sendAnthropic(
                message: message,
                modelID: model.modelID,
                apiKey: keys.anthropic,
                history: history,
                attachments: attachments
            )
        case .gemini:
            return try await sendGemini(
                message: message,
                modelID: model.modelID,
                apiKey: keys.gemini,
                history: history,
                attachments: attachments
            )
        case .openrouter:
            return try await sendOpenRouter(
                message: message,
                modelID: model.modelID,
                apiKey: keys.openRouter,
                history: history,
                attachments: attachments
            )
        case .openrouterFree:
            return try await sendOpenRouter(
                message: message,
                modelID: model.modelID,
                apiKey: nil,
                history: history,
                attachments: attachments
            )
        }
    }

    private func fetchOpenAIModels(apiKey: String) async -> [ModelOption] {
        guard let url = URL(string: "https://api.openai.com/v1/models") else { return [] }
        var request = URLRequest(url: url)
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await session.data(for: request)
            let decoded = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
            return decoded.data
                .map { ModelOption(provider: .openai, modelID: $0.id, displayName: $0.id) }
                .filter { $0.modelID.contains("gpt") || $0.modelID.contains("o") }
        } catch {
            return []
        }
    }

    private func fetchAnthropicModels(apiKey: String) async -> [ModelOption] {
        guard let url = URL(string: "https://api.anthropic.com/v1/models") else { return [] }
        var request = URLRequest(url: url)
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        do {
            let (data, _) = try await session.data(for: request)
            let decoded = try JSONDecoder().decode(AnthropicModelsResponse.self, from: data)
            return decoded.data.map { ModelOption(provider: .anthropic, modelID: $0.id, displayName: $0.displayName ?? $0.id) }
        } catch {
            return []
        }
    }

    private func fetchGeminiModels(apiKey: String) async -> [ModelOption] {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?key=\(apiKey)") else { return [] }

        do {
            let (data, _) = try await session.data(from: url)
            let decoded = try JSONDecoder().decode(GeminiModelsResponse.self, from: data)
            return decoded.models
                .filter { $0.supportedGenerationMethods?.contains("generateContent") == true }
                .map {
                    let id = $0.name.replacingOccurrences(of: "models/", with: "")
                    return ModelOption(provider: .gemini, modelID: id, displayName: id)
                }
        } catch {
            return []
        }
    }

    private func fetchOpenRouterModels(apiKey: String) async -> [ModelOption] {
        guard let url = URL(string: "https://openrouter.ai/api/v1/models") else { return [] }
        var request = URLRequest(url: url)
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await session.data(for: request)
            let decoded = try JSONDecoder().decode(OpenRouterModelsResponse.self, from: data)
            return decoded.data.map { ModelOption(provider: .openrouter, modelID: $0.id, displayName: $0.name ?? $0.id) }
        } catch {
            return []
        }
    }

    private func fetchOpenRouterFreeModels() async -> [ModelOption] {
        guard let url = URL(string: "https://openrouter.ai/api/v1/models") else { return [] }

        do {
            let (data, _) = try await session.data(from: url)
            let decoded = try JSONDecoder().decode(OpenRouterModelsResponse.self, from: data)
            return decoded.data
                .filter { model in
                    model.id.lowercased().contains(":free") ||
                    model.pricing?.prompt == "0" ||
                    model.pricing?.completion == "0"
                }
                .map { ModelOption(provider: .openrouterFree, modelID: $0.id, displayName: $0.name ?? $0.id) }
        } catch {
            return []
        }
    }

    private func sendOpenAI(
        message: String,
        modelID: String,
        apiKey: String,
        history: [ChatMessage],
        attachments: [AttachmentItem]
    ) async throws -> String {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else { throw APIError.invalidURL }
        let images = imageAttachments(from: attachments)
        let messages: [[String: Any]] = history.map { ["role": $0.role.rawValue, "content": $0.text] } + [[
            "role": "user",
            "content": openAIContent(text: message, images: images)
        ]]
        let body: [String: Any] = ["model": modelID, "messages": messages]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await session.data(for: request)
        return extractChatCompletionText(data: data)
    }

    private func sendAnthropic(
        message: String,
        modelID: String,
        apiKey: String,
        history: [ChatMessage],
        attachments: [AttachmentItem]
    ) async throws -> String {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { throw APIError.invalidURL }
        let images = imageAttachments(from: attachments)
        let messages: [[String: Any]] = history.map { ["role": $0.role.rawValue, "content": $0.text] } + [[
            "role": "user",
            "content": anthropicContent(text: message, images: images)
        ]]
        let body: [String: Any] = [
            "model": modelID,
            "max_tokens": 1200,
            "messages": messages
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await session.data(for: request)
        return extractAnthropicText(data: data)
    }

    private func sendGemini(
        message: String,
        modelID: String,
        apiKey: String,
        history: [ChatMessage],
        attachments: [AttachmentItem]
    ) async throws -> String {
        guard let escaped = modelID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(escaped):generateContent?key=\(apiKey)") else {
            throw APIError.invalidURL
        }
        let images = imageAttachments(from: attachments)
        let convertedHistory: [[String: Any]] = history.map {
            [
                "role": $0.role == .assistant ? "model" : "user",
                "parts": [["text": $0.text]]
            ]
        }

        var userParts: [[String: Any]] = [["text": message]]
        userParts.append(contentsOf: images.map { ["inline_data": ["mime_type": $0.mimeType, "data": $0.base64]] })
        let contents = convertedHistory + [["role": "user", "parts": userParts]]
        let body: [String: Any] = ["contents": contents]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await session.data(for: request)
        return extractGeminiText(data: data)
    }

    private func sendOpenRouter(
        message: String,
        modelID: String,
        apiKey: String?,
        history: [ChatMessage],
        attachments: [AttachmentItem]
    ) async throws -> String {
        guard let url = URL(string: "https://openrouter.ai/api/v1/chat/completions") else { throw APIError.invalidURL }
        let images = imageAttachments(from: attachments)
        let messages: [[String: Any]] = history.map { ["role": $0.role.rawValue, "content": $0.text] } + [[
            "role": "user",
            "content": openAIContent(text: message, images: images)
        ]]
        let body: [String: Any] = ["model": modelID, "messages": messages]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if let apiKey, !apiKey.isEmpty {
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await session.data(for: request)
        return extractChatCompletionText(data: data)
    }

    private func openAIContent(text: String, images: [ImageAttachment]) -> [[String: Any]] {
        var content: [[String: Any]] = [["type": "text", "text": text]]
        content.append(contentsOf: images.map { ["type": "image_url", "image_url": ["url": $0.dataURL]] })
        return content
    }

    private func anthropicContent(text: String, images: [ImageAttachment]) -> [[String: Any]] {
        var content: [[String: Any]] = [["type": "text", "text": text]]
        content.append(contentsOf: images.map {
            [
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": $0.mimeType,
                    "data": $0.base64
                ]
            ]
        })
        return content
    }

    private func imageAttachments(from attachments: [AttachmentItem]) -> [ImageAttachment] {
        attachments.compactMap { attachment in
            guard let mime = mimeType(for: attachment.url) else { return nil }
            guard mime.hasPrefix("image/") else { return nil }
            guard let data = try? Data(contentsOf: attachment.url), data.count <= 8_000_000 else { return nil }
            let base64 = data.base64EncodedString()
            return ImageAttachment(mimeType: mime, base64: base64, dataURL: "data:\(mime);base64,\(base64)")
        }
    }

    private func mimeType(for url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "webp": return "image/webp"
        case "gif": return "image/gif"
        case "heic": return "image/heic"
        case "heif": return "image/heif"
        default: return nil
        }
    }

    private func extractChatCompletionText(data: Data) -> String {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = object["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any]
        else {
            return "No response"
        }

        if let content = message["content"] as? String {
            return content
        }

        if let parts = message["content"] as? [[String: Any]] {
            let text = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
            return text.isEmpty ? "No response" : text
        }

        return "No response"
    }

    private func extractAnthropicText(data: Data) -> String {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = object["content"] as? [[String: Any]]
        else {
            return "No response"
        }
        let text = content.compactMap { $0["text"] as? String }.joined(separator: "\n")
        return text.isEmpty ? "No response" : text
    }

    private func extractGeminiText(data: Data) -> String {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = object["candidates"] as? [[String: Any]],
            let first = candidates.first,
            let content = first["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]]
        else {
            return "No response"
        }
        let text = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
        return text.isEmpty ? "No response" : text
    }
}

enum APIError: Error, LocalizedError {
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        }
    }
}

private struct ImageAttachment {
    let mimeType: String
    let base64: String
    let dataURL: String
}

private struct OpenAIModelsResponse: Decodable {
    struct Model: Decodable {
        let id: String
    }
    let data: [Model]
}

private struct AnthropicModelsResponse: Decodable {
    struct Model: Decodable {
        let id: String
        let displayName: String?

        enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
        }
    }
    let data: [Model]
}

private struct GeminiModelsResponse: Decodable {
    struct Model: Decodable {
        let name: String
        let supportedGenerationMethods: [String]?

        enum CodingKeys: String, CodingKey {
            case name
            case supportedGenerationMethods = "supportedGenerationMethods"
        }
    }
    let models: [Model]
}

private struct OpenRouterModelsResponse: Decodable {
    struct Pricing: Decodable {
        let prompt: String?
        let completion: String?
    }

    struct Model: Decodable {
        let id: String
        let name: String?
        let pricing: Pricing?
    }

    let data: [Model]
}
