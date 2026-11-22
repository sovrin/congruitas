import AppKit
import Combine

/// Owns the watched folders: stores and watches them, applies their rules,
/// and moves marked files to the Trash once their days are up.
final class Sorter: ObservableObject {
    /// A file marked for trashing, waiting for its date.
    struct Marked: Hashable {
        let url: URL
        let folder: String
        let trashAt: Date
    }

    struct LogLine: Identifiable {
        let id = UUID()
        let text: String
        let isError: Bool
    }

    @Published private(set) var folders: [WatchedFolder]
    @Published private(set) var marked: [Marked] = []
    @Published private(set) var log: [LogLine] = []
    /// Folders that couldn't be opened for watching (missing or unreadable), so their rules don't run.
    @Published private(set) var unwatched: Set<UUID> = []

    private let store: FolderStore
    private var watchers: [UUID: FolderWatcher] = [:]
    private var pending: [UUID: Task<Void, Never>] = [:]
    private var sweeper: Timer?

    init(store: FolderStore = FolderStore()) {
        self.store = store
        folders = store.load()
        folders.forEach(watch)
        // Marked files come due without any change in their folder, so look again every hour.
        sweeper = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scanAll() }
        }
    }

    // MARK: Folders

    func addFolder(_ url: URL) {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        guard !folders.contains(where: { $0.path == path }) else { return }
        let folder = WatchedFolder(path: path)
        folders.append(folder)
        save()
        watch(folder)
    }

    func removeFolder(_ folder: WatchedFolder) {
        folders.removeAll { $0.id == folder.id }
        watchers[folder.id] = nil
        unwatched.remove(folder.id)
        pending.removeValue(forKey: folder.id)?.cancel()
        marked.removeAll { $0.folder == folder.path }
        save()
    }

    func setRules(_ rules: [Rule], for folder: WatchedFolder) {
        guard let index = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        folders[index].rules = rules
        save()
        scan(folders[index])
    }

    func scanAll() {
        marked = folders.flatMap(found(in:)).sorted { $0.trashAt < $1.trashAt }
    }

    func scan(_ folder: WatchedFolder) {
        marked = (marked.filter { $0.folder != folder.path } + found(in: folder)).sorted { $0.trashAt < $1.trashAt }
    }

    // MARK: Marked files

    func keep(_ file: Marked) {
        do {
            try FileMarks.keep(file.url, in: file.folder)
            note("Kept \(file.url.lastPathComponent)")
        } catch {
            note("\(file.url.lastPathComponent): \(error.localizedDescription)", isError: true)
        }
        marked.removeAll { $0 == file }
    }

    func trashNow(_ file: Marked) {
        trash(file.url)
        marked.removeAll { $0 == file }
    }

    // MARK: Rules

    /// A file `rules` would act on now, and what would happen to it.
    struct Planned: Hashable {
        let name: String
        let rule: Rule.ID
        let outcome: String
    }

    /// What `rules` would do to the files in `folder` right now, without doing it.
    /// Skips the same files a scan skips: marked ones and ones this folder already handled.
    func preview(_ rules: [Rule], in folder: WatchedFolder) -> [Planned] {
        let files = (try? folder.files()) ?? []
        return files.compactMap { url in
            let name = url.lastPathComponent
            guard FileMarks.trashAt(url) == nil, FileMarks.done(url) != folder.path,
                  let (rule, value) = rules.firstMatch(name)
            else { return nil }
            let outcome = switch rule.action {
            case .move: moveOutcome(name, to: folder.target(value), of: folder)
            case .rename: "→ \(value)"
            case .trash: "Trash in \(rule.days) \(rule.days == 1 ? "day" : "days")"
            }
            return Planned(name: name, rule: rule.id, outcome: outcome)
        }
    }

    /// Applies the rules to every file in `folder` and returns the files still waiting to be trashed.
    private func found(in folder: WatchedFolder) -> [Marked] {
        let items: [URL]
        do {
            items = try folder.files()
        } catch {
            note("\(folder.displayPath): \(error.localizedDescription)", isError: true)
            return []
        }

        var marked: [Marked] = []
        for url in items {
            let name = url.lastPathComponent

            if let date = FileMarks.trashAt(url) {
                if !FileMarks.isTagged(url) {
                    // Removing the tag in Finder means "keep it".
                    attempt(name) { try FileMarks.keep(url, in: folder.path) }
                    note("Kept \(name): its tag was removed")
                } else if date <= .now {
                    trash(url)
                } else {
                    marked.append(Marked(url: url, folder: folder.path, trashAt: date))
                }
                continue
            }
            if FileMarks.done(url) == folder.path { continue }

            guard let (rule, value) = folder.rules.firstMatch(name) else { continue }
            attempt(name) {
                switch rule.action {
                case .move:
                    let dir = folder.target(value)
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    try place(url, as: name, in: dir, of: folder, renaming: false)
                case .rename:
                    guard !value.isEmpty, !value.contains("/"), value != name else {
                        throw CocoaError(.fileWriteInvalidFileName)
                    }
                    try place(url, as: value, in: url.deletingLastPathComponent(), of: folder, renaming: true)
                case .trash:
                    let date = Calendar.current.date(byAdding: .day, value: rule.days, to: .now) ?? .now
                    try FileMarks.mark(url, until: date)
                    marked.append(Marked(url: url, folder: folder.path, trashAt: date))
                    note("Marked \(name) for the Trash in \(rule.days) \(rule.days == 1 ? "day" : "days")")
                }
            }
        }
        return marked
    }

    private func moveOutcome(_ name: String, to dir: URL, of folder: WatchedFolder) -> String {
        let taken = FileManager.default.fileExists(atPath: dir.appending(path: name).path(percentEncoded: false))
        return "→ \(folder.display(dir))\(taken ? " · name taken" : "")"
    }

    /// Moves `url` into `dir` as `name` without overwriting. If an identical file already has that name,
    /// `url` is a duplicate and goes to the Trash; if a different file has it, `url` is kept as "name (1)".
    private func place(_ url: URL, as name: String, in dir: URL, of folder: WatchedFolder, renaming: Bool) throws {
        let original = url.lastPathComponent
        switch Placement.of(url, as: name, in: dir) {
        case .duplicate:
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            note(renaming ? "Trashed \(original): identical to \(name)"
                          : "Trashed \(original): identical file already in \(folder.display(dir))")
        case .free(let target):
            try FileManager.default.moveItem(at: url, to: target)
            let landed = target.lastPathComponent
            if renaming {
                try FileMarks.setDone(target, in: folder.path)
                note("Renamed \(original) → \(landed)")
            } else {
                note("Moved \(original) → \(folder.display(dir))\(landed == name ? "" : " as \(landed)")")
            }
        }
    }

    private func trash(_ url: URL) {
        let name = url.lastPathComponent
        attempt(name) {
            // Unmarked first, so a file put back from the Trash starts over instead of being trashed again.
            try FileMarks.clear(url)
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            note("Moved \(name) to the Trash")
        }
    }

    // MARK: Plumbing

    private func watch(_ folder: WatchedFolder) {
        let id = folder.id
        watchers[id] = FolderWatcher(path: folder.path) { [weak self] in self?.scheduleScan(id) }
        if watchers[id] == nil {
            unwatched.insert(id)
            note("Can't watch \(folder.displayPath)", isError: true)
        } else {
            unwatched.remove(id)
        }
        scan(folder)
    }

    /// A download or copy fires many events; wait until the folder has been quiet for a second.
    private func scheduleScan(_ id: UUID) {
        pending[id]?.cancel()
        pending[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self, let folder = folders.first(where: { $0.id == id }) else { return }
            scan(folder)
        }
    }

    private func save() {
        do {
            try store.save(folders)
        } catch {
            note("Could not save folders: \(error.localizedDescription)", isError: true)
        }
    }

    private func attempt(_ name: String, _ work: () throws -> Void) {
        do {
            try work()
        } catch {
            note("\(name): \(error.localizedDescription)", isError: true)
        }
    }

    private func note(_ text: String, isError: Bool = false) {
        // A failing rule fails again on every scan; show its error once.
        if isError, log.contains(where: { $0.isError && $0.text == text }) { return }
        log.insert(LogLine(text: text, isError: isError), at: 0)
        log = Array(log.prefix(50))
    }
}
