import Foundation

/// One rule of a watched folder. The first rule whose pattern matches a file's name acts on it.
struct Rule: Codable, Hashable, Identifiable {
    enum Action: String, Codable, CaseIterable, Identifiable {
        case move, rename, trash

        var id: Self { self }
        var label: String {
            switch self {
            case .move: "Move to"
            case .rename: "Rename to"
            case .trash: "Mark for Trash"
            }
        }
    }

    var id = UUID()
    var pattern = ""
    var action = Action.move
    /// Move: target folder, relative to the watched folder or absolute (~ allowed). Rename: the new name.
    /// Both take $0, $1… from the pattern's match.
    var template = ""
    /// Trash: how long a file stays marked before it goes to the Trash.
    var days = 7

    var regex: NSRegularExpression? { pattern.isEmpty ? nil : try? NSRegularExpression(pattern: pattern) }

    var isValid: Bool {
        regex != nil && (action == .trash ? days >= 1 : !template.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    /// The template with $1… filled in from `name`, or nil if the rule doesn't match.
    func resolve(_ name: String) -> String? {
        guard isValid, let regex,
              let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name))
        else { return nil }
        return regex.replacementString(for: match, in: name, offset: 0, template: template)
    }
}

extension [Rule] {
    /// The first rule that matches `name`, with its resolved template.
    func firstMatch(_ name: String) -> (rule: Rule, value: String)? {
        lazy.compactMap { rule in rule.resolve(name).map { (rule, $0) } }.first
    }
}

/// A folder congruitas watches, with its rules in order.
struct WatchedFolder: Codable, Hashable, Identifiable {
    var id = UUID()
    var path: String
    var rules: [Rule] = []

    var url: URL { URL(fileURLWithPath: path, isDirectory: true) }
    var name: String { url.lastPathComponent }
    var displayPath: String { path.tildePath }

    /// The files rules apply to: files and packages (.app, .rtfd) directly in the folder.
    /// Hidden files and plain subfolders, such as move targets, are left alone.
    func files() throws -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isPackageKey]
        return try FileManager.default
            .contentsOfDirectory(at: url, includingPropertiesForKeys: Array(keys), options: .skipsHiddenFiles)
            .filter { url in
                let values = try? url.resourceValues(forKeys: keys)
                return values?.isRegularFile == true || values?.isPackage == true
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// A path for showing: relative when inside this folder, otherwise with ~ for home.
    func display(_ target: URL) -> String {
        let base = url.path(percentEncoded: false), path = target.standardizedFileURL.path(percentEncoded: false)
        return path.hasPrefix(base) && path != base ? String(path.dropFirst(base.count)) : path.tildePath
    }

    /// A move rule's resolved template as a folder: absolute, ~, or relative to this folder.
    func target(_ template: String) -> URL {
        let expanded = (template as NSString).expandingTildeInPath
        return expanded.hasPrefix("/")
            ? URL(fileURLWithPath: expanded, isDirectory: true)
            : url.appending(path: expanded, directoryHint: .isDirectory)
    }
}

extension String {
    /// The path with the home directory shortened to ~.
    var tildePath: String { replacingOccurrences(of: NSHomeDirectory(), with: "~", options: .anchored) }
}
