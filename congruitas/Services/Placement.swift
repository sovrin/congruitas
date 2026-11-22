import Foundation

/// Where a file lands when it moves into a folder under a name. Never overwrites anything.
enum Placement: Equatable {
    /// Free to move here: under its own name, or "name (1)" when a different file has that name.
    case free(URL)
    /// An identical file already has that name, so the incoming one is a duplicate.
    case duplicate(of: URL)

    static func of(_ file: URL, as name: String, in dir: URL) -> Placement {
        let target = dir.appending(path: name)
        guard exists(target) else { return .free(target) }
        if sameContent(file, target) { return .duplicate(of: target) }
        let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        var n = 1
        while true {
            let candidate = dir.appending(path: ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)")
            if !exists(candidate) { return .free(candidate) }
            n += 1
        }
    }

    private static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    private static func sameContent(_ a: URL, _ b: URL) -> Bool {
        let size = { (url: URL) in try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize }
        // Different sizes can't match, so big files aren't read for nothing. Packages have no size and get compared.
        guard size(a) == size(b) else { return false }
        return FileManager.default.contentsEqual(atPath: a.path(percentEncoded: false), andPath: b.path(percentEncoded: false))
    }
}
