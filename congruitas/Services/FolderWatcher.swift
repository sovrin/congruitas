import Foundation

/// Calls `onChange` when a folder's entries change (added, removed, renamed). Top level only.
final class FolderWatcher {
    private let source: DispatchSourceFileSystemObject

    init?(path: String, onChange: @escaping () -> Void) {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { MainActor.assumeIsolated(onChange) }
        source.setCancelHandler { close(fd) }
        source.resume()
    }

    deinit { source.cancel() }
}
