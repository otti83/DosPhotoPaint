import SwiftUI

struct ShortcutsSettingsView: View {
    @State private var query = ""
    @State private var entries: [ShortcutEntry] = []

    private var filtered: [ShortcutEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return entries }
        return entries.filter {
            $0.title.localizedCaseInsensitiveContains(q) || $0.keys.localizedCaseInsensitiveContains(q)
                || $0.section.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField(String(localized: "Search shortcuts", table: "Settings"), text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(12)
            Table(filtered) {
                TableColumn(String(localized: "Command", table: "Settings"), value: \.title)
                TableColumn(String(localized: "Shortcut", table: "Settings")) { entry in
                    Text(entry.keys).monospaced()
                }.width(min: 80, ideal: 110, max: 160)
                TableColumn(String(localized: "Menu", table: "Settings"), value: \.section)
                    .width(min: 80, ideal: 110, max: 160)
            }
        }
        .onAppear { entries = ShortcutCatalog.entries() }
    }
}
