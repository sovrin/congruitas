// Self-check for the rule logic and file marks. Run: checks/run.sh
import Foundation

func check(_ ok: Bool, _ what: String, line: Int = #line) {
    if !ok { print("FAIL line \(line): \(what)"); exit(1) }
}

// Rule.resolve: templates take capture groups; no match or invalid rule → nil.
let pdf = Rule(pattern: #"(?i)^(.+)\.pdf$"#, action: .rename, template: "doc-$1.pdf")
check(pdf.resolve("Invoice.PDF") == "doc-Invoice.pdf", "rename with capture group")
check(pdf.resolve("notes.txt") == nil, "no match")
check(Rule(pattern: "(", action: .move, template: "x").resolve("(") == nil, "invalid regex never matches")
check(Rule(pattern: ".*", action: .move, template: " ").resolve("a") == nil, "blank template is invalid")
check(Rule(pattern: "a", action: .trash, days: 0).isValid == false, "trash needs at least one day")
check(Rule(pattern: "a", action: .trash).resolve("a") != nil, "trash rule ignores template")

// WatchedFolder.target: relative, ~ and absolute.
let folder = WatchedFolder(path: "/tmp/w")
check(folder.target("PDFs").path(percentEncoded: false) == "/tmp/w/PDFs/", "relative target")
check(folder.target("/x/y").path(percentEncoded: false) == "/x/y/", "absolute target")
check(folder.target("~/z").path(percentEncoded: false) == NSHomeDirectory() + "/z/", "tilde target")
check(folder.display(folder.target("PDFs/$1")) == "PDFs/$1/", "inside the folder shows relative")
check(folder.display(folder.target("~/z")) == "~/z/", "elsewhere shows with ~")
check(folder.display(folder.target(".")) == "/tmp/w/", "the folder itself stays absolute")

// FileMarks round trip on a real file, keeping a tag the user set.
let dir = FileManager.default.temporaryDirectory.appending(path: "congruitas-check-\(UUID())")
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: dir) }
let file = dir.appending(path: "a.txt")
try Data("x".utf8).write(to: file)
var values = URLResourceValues()
values.tagNames = ["Work"]
var tagged = file
try tagged.setResourceValues(values)

let due = Date(timeIntervalSince1970: 2_000_000_000)
try FileMarks.mark(file, until: due)
check(FileMarks.trashAt(file) == due, "trash date stored")
check(FileMarks.isTagged(file), "tag set")
let names = try file.resourceValues(forKeys: [.tagNamesKey]).tagNames ?? []
check(Set(names) == ["Work", FileMarks.tag], "Finder sees both tags: \(names)")

try FileMarks.keep(file, in: dir.path)
check(FileMarks.trashAt(file) == nil && !FileMarks.isTagged(file), "keep clears the mark")
check(FileMarks.done(file) == dir.path, "keep remembers the folder")
let after = try URL(fileURLWithPath: file.path).resourceValues(forKeys: [.tagNamesKey]).tagNames ?? []
check(after == ["Work"], "user tag survives: \(after)")
try FileMarks.clear(file) // clearing an unmarked file is fine

// firstMatch: the first matching rule wins.
let rules = [Rule(pattern: #"\.txt$"#, action: .move, template: "Text"), Rule(pattern: "a", action: .trash)]
check(rules.firstMatch("a.txt")?.rule.id == rules[0].id, "first rule wins")
check(rules.firstMatch("a.md")?.rule.id == rules[1].id, "falls through to the next rule")
check(rules.firstMatch("b.md") == nil, "no rule matches")

// files(): files only, no hidden files or subfolders.
try Data().write(to: dir.appending(path: ".hidden"))
try FileManager.default.createDirectory(at: dir.appending(path: "Sub"), withIntermediateDirectories: true)
let listed = try WatchedFolder(path: dir.path).files().map(\.lastPathComponent)
check(listed == ["a.txt"], "only plain files listed: \(listed)")

// Placement: never overwrite; identical → duplicate, different → "name (1)", "name (2)".
let target = dir.appending(path: "Target")
try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
let incoming = dir.appending(path: "song.gp5")
try Data("tab".utf8).write(to: incoming)
check(Placement.of(incoming, as: "song.gp5", in: target) == .free(target.appending(path: "song.gp5")), "free name")
try Data("tab".utf8).write(to: target.appending(path: "song.gp5"))
check(Placement.of(incoming, as: "song.gp5", in: target) == .duplicate(of: target.appending(path: "song.gp5")), "identical is a duplicate")
try Data("tob".utf8).write(to: target.appending(path: "song.gp5"))
check(Placement.of(incoming, as: "song.gp5", in: target) == .free(target.appending(path: "song (1).gp5")), "different keeps both")
try Data("x".utf8).write(to: target.appending(path: "song (1).gp5"))
check(Placement.of(incoming, as: "song.gp5", in: target) == .free(target.appending(path: "song (2).gp5")), "next free number")
try Data("x".utf8).write(to: target.appending(path: "README"))
check(Placement.of(incoming, as: "README", in: target) == .free(target.appending(path: "README (1)")), "no extension")

print("ok")
