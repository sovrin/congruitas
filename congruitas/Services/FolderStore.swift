import Foundation

/// The watched folders and their rules, in ~/Library/Application Support/Congruitas/folders.json.
struct FolderStore {
    var url: URL = {
        let dir = URL.applicationSupportDirectory.appending(path: "Congruitas")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "folders.json")
    }()

    func load() -> [WatchedFolder] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([WatchedFolder].self, from: data)) ?? []
    }

    func save(_ folders: [WatchedFolder]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(folders).write(to: url, options: .atomic)
    }
}
