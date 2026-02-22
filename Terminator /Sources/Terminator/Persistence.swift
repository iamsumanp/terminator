import Foundation

enum Persistence {
    static func stateURL() throws -> URL {
        let fm = FileManager.default
        let base = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent("Terminator", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("state.json")
    }

    static func loadState() -> PersistedState {
        do {
            let url = try stateURL()
            guard FileManager.default.fileExists(atPath: url.path) else {
                return PersistedState(keys: ProviderKeys(), selectedModelID: nil, messages: [])
            }
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(PersistedState.self, from: data)
        } catch {
            return PersistedState(keys: ProviderKeys(), selectedModelID: nil, messages: [])
        }
    }

    static func saveState(_ state: PersistedState) {
        do {
            let data = try JSONEncoder().encode(state)
            let url = try stateURL()
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("Failed to save state: \(error.localizedDescription)")
        }
    }
}
