import Paritas
import SwiftUI

/// Edits a folder's rules on a copy. Nothing runs until Save, so a half-typed pattern can't move files.
/// Rules show as one-line summaries; only new rules and the ones you click open in edit mode.
struct RulesEditor: View {
    let folder: WatchedFolder
    let preview: ([Rule]) -> [Sorter.Planned]
    let onSave: ([Rule]) -> Void
    @State private var draft: [Rule]
    @State private var planned: [Sorter.Planned] = []
    @State private var editing: Set<Rule.ID> = []

    init(folder: WatchedFolder, preview: @escaping ([Rule]) -> [Sorter.Planned], onSave: @escaping ([Rule]) -> Void) {
        self.folder = folder
        self.preview = preview
        self.onSave = onSave
        _draft = State(initialValue: folder.rules)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if draft.isEmpty {
                Text("No rules yet. The first rule that matches a file's name acts on it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach($draft) { $rule in
                let matches = planned.filter { $0.rule == rule.id }
                if editing.contains(rule.id) {
                    RuleRow(rule: $rule, matches: matches) {
                        editing.remove(rule.id)
                    } onDelete: {
                        draft.removeAll { $0.id == rule.id }
                    }
                } else {
                    RuleSummary(rule: rule, matches: matches.count) {
                        editing.insert(rule.id)
                    } onDelete: {
                        draft.removeAll { $0.id == rule.id }
                    }
                }
            }
            HStack {
                Button("Add Rule", systemImage: "plus") {
                    let rule = Rule()
                    draft.append(rule)
                    editing.insert(rule.id)
                }
                Spacer()
                if draft != folder.rules {
                    Text("Saving acts on \(planned.count) \(planned.count == 1 ? "file" : "files")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Revert") {
                        draft = folder.rules
                        editing = []
                    }
                    Button("Save") {
                        onSave(draft)
                        editing = []
                    }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!draft.allSatisfy(\.isValid))
                }
            }
            .controlSize(.small)
        }
        // Waits for a pause in typing, then looks at the folder again.
        .task(id: draft) {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            planned = preview(draft)
        }
    }
}

/// A rule in one line: pattern, what it does, and how many files it would act on now. Click to edit.
private struct RuleSummary: View {
    let rule: Rule
    let matches: Int
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HoverRow(action: onEdit) {
            VStack(alignment: .leading, spacing: 1) {
                Text(rule.pattern).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle)
                Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if matches > 0 {
                RowBadge("\(matches) \(matches == 1 ? "file" : "files")")
            }
        } actions: {
            RoundIconButton(systemImage: "pencil", help: "Edit rule", action: onEdit)
            RoundIconButton(systemImage: "xmark", help: "Remove rule", action: onDelete)
        }
        // Same frame as the row's hover highlight, so same radius.
        .background(Color.primary.opacity(PanelMetrics.fill),
                    in: RoundedRectangle(cornerRadius: PanelMetrics.rowRadius, style: .continuous))
        .contextMenu {
            Button("Edit Rule", action: onEdit)
            Button("Remove Rule", action: onDelete)
        }
    }

    private var summary: String {
        switch rule.action {
        case .move, .rename: "\(rule.action.label) \(rule.template)"
        case .trash: "\(rule.action.label) after \(rule.days) \(rule.days == 1 ? "day" : "days")"
        }
    }
}

private struct RuleRow: View {
    @Binding var rule: Rule
    /// Files in the folder this rule would act on now. A file belongs to the first rule that matches it.
    let matches: [Sorter.Planned]
    let onDone: () -> Void
    let onDelete: () -> Void
    @State private var showsAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                TextField("Pattern, e.g. (?i)\\.pdf$", text: $rule.pattern)
                    .foregroundStyle(rule.pattern.isEmpty || rule.regex != nil ? Color.primary : Color.red)
                    .help(rule.pattern.isEmpty || rule.regex != nil ? "Regex matched against the file name" : "Invalid regex")
                RoundIconButton(systemImage: "checkmark", help: "Done editing", action: onDone)
                    .disabled(!rule.isValid)
                RoundIconButton(systemImage: "xmark", help: "Remove rule", action: onDelete)
            }
            HStack(spacing: 4) {
                Picker("Action", selection: $rule.action) {
                    ForEach(Rule.Action.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                if rule.action == .trash {
                    Stepper("after \(rule.days) \(rule.days == 1 ? "day" : "days")", value: $rule.days, in: 1...365)
                } else {
                    TextField(rule.action == .move ? "Folder, e.g. PDFs or ~/Documents/$1" : "New name, e.g. $1.pdf",
                              text: $rule.template)
                }
            }
            if rule.isValid { matchList }
        }
        .font(.callout.monospaced())
        .textFieldStyle(.roundedBorder)
        .controlSize(.small)
        .padding(8)
        .background(Color.primary.opacity(PanelMetrics.fill),
                    in: RoundedRectangle(cornerRadius: PanelMetrics.cardRadius, style: .continuous))
    }

    private var matchList: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(matches.isEmpty ? "No files match now" : "Matches \(matches.count) \(matches.count == 1 ? "file" : "files") now")
                .foregroundStyle(.secondary)
            ForEach(showsAll ? matches : Array(matches.prefix(5)), id: \.self) { file in
                HStack(spacing: 6) {
                    Text(file.name).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(file.outcome).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                }
            }
            if matches.count > 5 {
                Button(showsAll ? "Show fewer" : "and \(matches.count - 5) more") { showsAll.toggle() }
                    .buttonStyle(.link)
            }
        }
        .font(.caption)
    }
}
