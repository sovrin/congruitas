import AppKit
import Paritas
import SwiftUI

/// Menu bar panel, built from the shared Paritas components.
struct MenuContent: View {
    @ObservedObject var sorter: Sorter
    @State private var expanded: UUID?

    var body: some View {
        MenuPanel {
            PanelHeader("congruitas", status: status, icon: Image("MenuBarIcon"), colors: [.indigo, .purple])
            if let warning {
                WarningCard(warning.title, message: warning.message)
            }
            PanelDivider()
            folders
            if !sorter.marked.isEmpty {
                PanelDivider()
                marked
            }
            if !sorter.log.isEmpty {
                PanelDivider()
                activity
            }
            PanelDivider()
            PanelFooter(appName: "congruitas")
        }
    }

    // MARK: Header

    private var status: String {
        let folders = sorter.folders.count
        let marked = sorter.marked.count
        var text = "\(folders) \(folders == 1 ? "folder" : "folders") watched"
        if marked > 0 { text += " · \(marked) marked for Trash" }
        return text
    }

    private var warning: (title: String, message: String)? {
        let names = sorter.folders.filter { sorter.unwatched.contains($0.id) }.map(\.name)
        guard let first = names.first else { return nil }
        return names.count == 1
            ? ("Can't watch \(first)", "The folder is missing or unreadable, so its rules don't run.")
            : ("Can't watch \(names.count) folders", "\(names.formatted()) are missing or unreadable, so their rules don't run.")
    }

    // MARK: Folders

    private var folders: some View {
        PanelSection("Folders") {
            if sorter.folders.isEmpty {
                EmptyState("No folders watched", systemImage: "folder",
                           hint: Text("Each folder gets its own rules for sorting new files."))
            }
            ForEach(sorter.folders) { folder in
                folderRow(folder)
                if expanded == folder.id {
                    RulesEditor(folder: folder, preview: { sorter.preview($0, in: folder) }) {
                        sorter.setRules($0, for: folder)
                    }
                        .padding(.horizontal, PanelMetrics.inset)
                        .padding(.vertical, 6)
                }
            }
            Button(action: addFolder) {
                Label("Watch Folder…", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(HoverButtonStyle())
            .padding(.horizontal, PanelMetrics.rowInset)
        }
    }

    private func folderRow(_ folder: WatchedFolder) -> some View {
        HoverRow {
            withAnimation(.smooth(duration: 0.2)) { expanded = expanded == folder.id ? nil : folder.id }
        } content: {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(expanded == folder.id ? 90 : 0))
                .frame(width: 19)
            VStack(alignment: .leading, spacing: 0) {
                Text(folder.name).lineLimit(1)
                Text(folder.displayPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 8)
            RowBadge("\(folder.rules.count) \(folder.rules.count == 1 ? "rule" : "rules")")
        } actions: {
            RoundIconButton(systemImage: "arrow.clockwise", help: "Run rules now") { sorter.scan(folder) }
            RoundIconButton(systemImage: "xmark", help: "Stop watching") { sorter.removeFolder(folder) }
        }
        .padding(.horizontal, PanelMetrics.rowInset)
        .contextMenu {
            Button("Show in Finder") { showInFinder(folder.url) }
            Button("Run Rules Now") { sorter.scan(folder) }
            Divider()
            Button("Stop Watching") { sorter.removeFolder(folder) }
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Watch"
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(sorter.addFolder)
    }

    // MARK: Marked

    private var marked: some View {
        PanelSection("Marked for Trash") {
            ForEach(sorter.marked, id: \.self) { file in
                HoverRow {
                    showInFinder(file.url)
                } content: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .frame(width: 19)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(file.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                        Text(file.folder.tildePath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                    Spacer(minLength: 8)
                    RowBadge(Text(file.trashAt, format: .relative(presentation: .named)))
                } actions: {
                    RoundIconButton(systemImage: "arrow.uturn.backward", help: "Keep this file") { sorter.keep(file) }
                    RoundIconButton(systemImage: "trash", help: "Move to Trash now") { sorter.trashNow(file) }
                }
                .padding(.horizontal, PanelMetrics.rowInset)
                .contextMenu {
                    Button("Show in Finder") { showInFinder(file.url) }
                    Button("Keep") { sorter.keep(file) }
                    Divider()
                    Button("Move to Trash Now") { sorter.trashNow(file) }
                }
            }
        }
    }

    // MARK: Activity

    private var activity: some View {
        PanelSection("Recent") {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(sorter.log.prefix(6)) { line in
                    Label(line.text, systemImage: line.isError ? "exclamationmark.triangle.fill" : "checkmark")
                        .font(.caption)
                        .foregroundStyle(line.isError ? Color.orange : Color.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(line.text)
                }
            }
            .padding(.horizontal, PanelMetrics.inset)
        }
    }
}
