import AppKit
import SwiftUI

let app = NSApplication.shared

func cli(_ flag: String, _ render: (Stats, StatsStore, Double) -> NSImage?) {
    guard let i = CommandLine.arguments.firstIndex(of: flag), i + 1 < CommandLine.arguments.count else { return }
    let store = StatsStore()
    do {
        let s = try store.loadNow()
        let t = i + 2 < CommandLine.arguments.count ? Double(CommandLine.arguments[i + 2]) ?? 0 : 0
        guard let png = render(s, store, t)?.png else { exit(2) }
        try png.write(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
        print("\(s.rank) \(s.xp) XP")
        exit(0)
    } catch {
        FileHandle.standardError.write("\(flag) failed: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}
cli("--snapshot") { s, store, _ in MainActor.assumeIsolated { DashboardContent.render(s, store: store) } }
cli("--card") { s, _, _ in Share.render(s) }
cli("--setup") { s, store, t in
    MainActor.assumeIsolated { () -> NSImage? in
        let st = SetupStatus(shell: false, claude: false, claudeInstalled: true, commands: s.total)
        let r = ImageRenderer(content: SetupView(store: store, status: st, startStep: Int(t)))
        r.scale = 2
        return r.nsImage
    }
}
cli("--tiers") { s, _, _ in
    MainActor.assumeIsolated { () -> NSImage? in
        let r = ImageRenderer(content: LadderPage(s: s, scroll: false).frame(width: 470).background(Color(nsColor: .windowBackgroundColor)))
        r.scale = 2
        return r.nsImage
    }
}
cli("--compact") { s, store, _ in
    MainActor.assumeIsolated { () -> NSImage? in
        let r = ImageRenderer(content: DashboardContent(s: s, store: store, forImage: true, compact: true)
            .background(Color(nsColor: .windowBackgroundColor)))
        r.scale = 2
        return r.nsImage
    }
}
cli("--settings") { s, _, _ in
    MainActor.assumeIsolated { () -> NSImage? in
        let r = ImageRenderer(content: SettingsView(s: s).background(Color(nsColor: .windowBackgroundColor)))
        r.scale = 2
        return r.nsImage
    }
}
cli("--reveal") { s, _, t in
    MainActor.assumeIsolated { () -> NSImage? in
        let r = ImageRenderer(content: RevealView(plan: RevealPlan(from: nil, to: s), fixedTime: t))
        r.scale = 2
        return r.nsImage
    }
}

let delegate = AppDelegate()
app.delegate = delegate
app.run()
