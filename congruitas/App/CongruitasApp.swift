import SwiftUI

@main
struct CongruitasApp: App {
    @StateObject private var sorter = Sorter()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(sorter: sorter)
        } label: {
            Image(sorter.marked.isEmpty ? "MenuBarIcon" : "MenuBarIconMarked")
                .accessibilityLabel("congruitas")
        }
        .menuBarExtraStyle(.window)
    }
}
