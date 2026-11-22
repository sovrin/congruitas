import Foundation

/// What congruitas remembers about a file. Kept in extended attributes, so it moves with the file.
enum FileMarks {
    /// Finder tag on files marked for trashing.
    static let tag = "To Trash"

    private static let trashAtKey = "com.sovrin.congruitas.trash-at"
    private static let doneKey = "com.sovrin.congruitas.done"
    private static let tagsKey = "com.apple.metadata:_kMDItemUserTags"
    /// Finder stores a tag as "name\ncolor"; 6 is red.
    private static let taggedValue = "\(tag)\n6"

    // MARK: Marked for Trash

    static func trashAt(_ url: URL) -> Date? {
        read(trashAtKey, url)
            .flatMap { String(data: $0, encoding: .utf8) }
            .flatMap(Double.init)
            .map(Date.init(timeIntervalSince1970:))
    }

    static func mark(_ url: URL, until date: Date) throws {
        try write(trashAtKey, Data(String(date.timeIntervalSince1970).utf8), url)
        try setTags(tags(url).filter { !isOurTag($0) } + [taggedValue], url)
    }

    /// Removes the mark and the tag, e.g. right before the file goes to the Trash.
    static func clear(_ url: URL) throws {
        try write(trashAtKey, nil, url)
        try setTags(tags(url).filter { !isOurTag($0) }, url)
    }

    /// The user wants to keep the file: clear the mark and don't let `folder`'s rules mark it again.
    static func keep(_ url: URL, in folder: String) throws {
        try clear(url)
        try setDone(url, in: folder)
    }

    static func isTagged(_ url: URL) -> Bool { tags(url).contains(where: isOurTag) }

    // MARK: Done

    /// The folder whose rules already acted on the file and left it there (renamed or kept).
    /// Stops a rename whose result still matches from looping. Holds the folder path, so a file
    /// moved into another watched folder still gets that folder's rules.
    static func done(_ url: URL) -> String? {
        read(doneKey, url).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func setDone(_ url: URL, in folder: String) throws {
        try write(doneKey, Data(folder.utf8), url)
    }

    // MARK: Plumbing

    private static func isOurTag(_ value: String) -> Bool { value == tag || value.hasPrefix(tag + "\n") }

    private static func tags(_ url: URL) -> [String] {
        read(tagsKey, url).flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String] } ?? []
    }

    private static func setTags(_ tags: [String], _ url: URL) throws {
        let data = tags.isEmpty ? nil : try PropertyListSerialization.data(fromPropertyList: tags, format: .binary, options: 0)
        try write(tagsKey, data, url)
    }

    private static func read(_ name: String, _ url: URL) -> Data? {
        let path = url.path(percentEncoded: false)
        let size = getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
        guard size > 0 else { return nil }
        var data = Data(count: size)
        let read = data.withUnsafeMutableBytes { getxattr(path, name, $0.baseAddress, size, 0, XATTR_NOFOLLOW) }
        return read == size ? data : nil
    }

    /// Writes the attribute, or removes it when `data` is nil (removing a missing one is fine).
    private static func write(_ name: String, _ data: Data?, _ url: URL) throws {
        let path = url.path(percentEncoded: false)
        let result = if let data {
            data.withUnsafeBytes { setxattr(path, name, $0.baseAddress, data.count, 0, XATTR_NOFOLLOW) }
        } else {
            removexattr(path, name, XATTR_NOFOLLOW)
        }
        guard result != 0, !(data == nil && errno == ENOATTR) else { return }
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
