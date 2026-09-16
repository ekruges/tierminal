import AppKit
import SwiftUI

enum MenuBar {
    static let keys: [(key: String, label: String, on: Bool)] = [
        ("bar.emblem", "Rank emblem", true),
        ("bar.rank", "Rank name", true),
        ("bar.xp", "XP", true),
        ("bar.today", "Commands today", false),
        ("bar.total", "Commands total", false),
        ("bar.streak", "Streak", false),
        ("bar.ai", "Share run by AI", false),
        ("bar.short", "Compact numbers (26.8k)", true),
    ]

    static func on(_ key: String) -> Bool {
        let d = UserDefaults.standard
        return d.object(forKey: key) == nil ? (keys.first { $0.key == key }?.on ?? false) : d.bool(forKey: key)
    }

    static func title(_ s: Stats) -> String {
        let n: (Int) -> String = { on("bar.short") ? Fmt.short($0) : Fmt.num($0) }
        var parts: [String] = []
        if on("bar.rank") { parts.append(s.rank) }
        if on("bar.xp") { parts.append(n(s.xp) + " XP") }
        if on("bar.today") { parts.append(n(s.today) + " today") }
        if on("bar.total") { parts.append(n(s.total) + " cmds") }
        if on("bar.streak") { parts.append("\(s.streak)d streak") }
        if on("bar.ai") { parts.append("\(Int((s.aiShare * 100).rounded()))% AI") }
        return parts.joined(separator: " · ")
    }

    static var showEmblem: Bool { on("bar.emblem") }
}

struct SettingsView: View {
    let s: Stats
    var done: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("SETTINGS").font(.system(size: 10, weight: .semibold)).kerning(0.8).foregroundStyle(.secondary)
                Spacer()
                Button("Done", action: done)
            }
            Text("Menu bar shows").font(.headline)
            MenuBarToggles(s: s)
            Spacer()
        }
        .padding(16)
        .frame(width: 470, height: 700, alignment: .topLeading)
    }
}
