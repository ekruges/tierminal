import AppKit
import ServiceManagement
import SwiftUI

final class StatsStore: ObservableObject {
    @Published var stats: Stats?
    @Published var error: String?
    @Published var busy = false
    @Published var opens = 0
    var onChange: (() -> Void)?

    let script: String = {
        let fm = FileManager.default
        var cands: [String] = []
        if let r = Bundle.main.resourceURL { cands.append(r.appendingPathComponent("tierminal.py").path) }
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        cands.append(exe.appendingPathComponent("tierminal.py").path)
        cands.append(fm.currentDirectoryPath + "/tierminal.py")
        return cands.first { fm.fileExists(atPath: $0) } ?? cands[0]
    }()

    func loadNow() throws -> Stats {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        p.arguments = [script, "stats"]
        let out = Pipe()
        p.standardOutput = out
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return try JSONDecoder().decode(Stats.self, from: data)
    }

    func refresh() {
        EmblemImages.reset()
        run(["stats"]) { [self] data in
            do {
                stats = try JSONDecoder().decode(Stats.self, from: data)
                error = nil
            } catch {
                self.error = "stats failed: \(error)"
            }
            onChange?()
        }
    }

    func backfill() { longRun(["rescan"]) }
    func sync() { longRun(["sync"]) }

    func exec(_ args: [String], _ done: @escaping (String) -> Void) {
        run(args) { data in done(String(data: data, encoding: .utf8) ?? "") }
    }

    private func longRun(_ args: [String]) {
        busy = true
        run(args) { [self] _ in
            busy = false
            refresh()
        }
    }

    private func run(_ args: [String], _ done: @escaping (Data) -> Void) {
        let script = self.script
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            p.arguments = [script] + args
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            do { try p.run() } catch {
                DispatchQueue.main.async { self.error = "\(error)"; self.onChange?() }
                return
            }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            DispatchQueue.main.async { done(data) }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = StatsStore()
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private var statusCache: [Int: NSImage] = [:]
    private var revealWindow: NSWindow?
    private var setupWindow: NSWindow?
    private var launched = false
    private var setupChecked = false
    private var pending: Snapshot?
    private var pulseTimer: Timer?
    private var pulseOn = false

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = item.button {
            b.imagePosition = .imageLeading
            b.title = " …"
            b.target = self
            b.action = #selector(clicked)
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: Dashboard(store: store))
        store.onChange = { [weak self] in self?.render() }
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.render()
        }
        store.refresh()
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.store.refresh() }
        Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            guard let self, let s = self.store.stats, !s.remotes.isEmpty, !self.store.busy else { return }
            self.store.sync()
        }
        if Bundle.main.bundlePath.hasSuffix(".app") {
            do { try SMAppService.mainApp.register() } catch { NSLog("login item: \(error)") }
            exportBashEnv()
        }
    }

    private func exportBashEnv() {
        guard let hook = Bundle.main.resourceURL?.appendingPathComponent("tierminal.bash").path else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["setenv", "BASH_ENV", hook]
        try? p.run()
    }

    private func statusImage(_ s: Stats) -> NSImage {
        if let hit = statusCache[s.rankKey] { return hit }
        let img: NSImage
        if let custom = EmblemImages.image(tier: s.tier, division: s.division), let copy = custom.copy() as? NSImage {
            copy.size = NSSize(width: 20, height: 20)
            img = copy
        } else {
            let rendered = MainActor.assumeIsolated { () -> NSImage? in
                let r = ImageRenderer(content: EmblemView(tier: s.tier, division: s.division, size: 20, animated: false, pips: false).padding(1))
                r.scale = 2
                return r.nsImage
            }
            img = rendered ?? NSImage(size: NSSize(width: 20, height: 20))
            img.size = NSSize(width: 22, height: 22)
        }
        statusCache[s.rankKey] = img
        return img
    }

    private var rendering = false

    private func render() {
        guard !rendering, let b = item.button else { return }
        rendering = true
        defer { rendering = false }
        guard let s = store.stats else {
            b.title = store.error == nil ? " …" : " !"
            return
        }
        let title = MenuBar.title(s)
        b.image = MenuBar.showEmblem || title.isEmpty ? statusImage(s) : nil
        b.title = (title.isEmpty ? "" : " " + title) + (pending != nil ? " ▲" : "")
        updatePulse(s)
        if !setupChecked {
            setupChecked = true
            checkSetup()
            return
        }
        if setupWindow == nil { checkReveal(s) }
    }

    private func checkSetup() {
        store.exec(["setup", "status"]) { [weak self] out in
            guard let self else { return }
            guard let st = try? JSONDecoder().decode(SetupStatus.self, from: Data(out.utf8)) else {
                if let s = self.store.stats { self.checkReveal(s) }
                return
            }
            if st.complete && (st.commands > 0 || UserDefaults.standard.integer(forKey: "seen.rankKey") > 0) {
                if let s = self.store.stats { self.checkReveal(s) }
            } else {
                self.showSetup(st)
            }
        }
    }

    private func showSetup(_ st: SetupStatus, step: Int = 0) {
        setupWindow?.close()
        let w = RevealWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 560), styleMask: [.borderless], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.level = .floating
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: SetupView(store: store, status: st, done: { [weak self] in
            self?.setupWindow?.close()
            self?.setupWindow = nil
            self?.store.refresh()
        }, startStep: step))
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        setupWindow = w
    }

    private func checkReveal(_ s: Stats) {
        let d = UserDefaults.standard
        let seen = d.integer(forKey: "seen.rankKey")
        if seen == 0 {
            showReveal(from: nil, to: s)
            saveSeen(s)
        } else if s.rankKey > seen {
            if pending == nil {
                pending = Snapshot(total: d.integer(forKey: "seen.total"), xp: d.integer(forKey: "seen.xp"), rankKey: seen)
                updatePulse(s)
            }
        } else if !launched || s.rankKey < seen {
            launched = true
            saveSeen(s)
        }
        launched = true
    }

    private func saveSeen(_ s: Stats) {
        let d = UserDefaults.standard
        d.set(s.rankKey, forKey: "seen.rankKey")
        d.set(s.total, forKey: "seen.total")
        d.set(s.xp, forKey: "seen.xp")
    }

    private func updatePulse(_ s: Stats) {
        let near = s.divEnd != nil && s.progress >= 0.9
        let interval: Double? = pending != nil ? 0.55 : (near ? 1.4 : nil)
        guard let interval else {
            pulseTimer?.invalidate()
            pulseTimer = nil
            item.button?.alphaValue = 1
            return
        }
        if let t = pulseTimer, abs(t.timeInterval - interval) < 0.01 { return }
        pulseTimer?.invalidate()
        pulseTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self, let b = self.item.button else { return }
            self.pulseOn.toggle()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = interval * 0.9
                b.animator().alphaValue = self.pulseOn ? 0.35 : 1
            }
        }
    }

    private func showReveal(from: Snapshot?, to s: Stats) {
        revealWindow?.close()
        let w = RevealWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 720), styleMask: [.borderless], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.level = .floating
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: RevealView(plan: RevealPlan(from: from, to: s)) { [weak self] in
            self?.revealWindow?.close()
            self?.revealWindow = nil
        })
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        revealWindow = w
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { showMenu(); return }
        guard let b = item.button else { return }
        if let p = pending, let s = store.stats {
            pending = nil
            saveSeen(s)
            updatePulse(s)
            b.title = b.title.replacingOccurrences(of: " ▲", with: "")
            showReveal(from: p, to: s)
            return
        }
        if popover.isShown { popover.performClose(nil); return }
        statusCache.removeAll()
        store.opens += 1
        store.refresh()
        popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showMenu() {
        let m = NSMenu()
        m.addItem(withTitle: "Refresh", action: #selector(refresh), keyEquivalent: "")
        m.addItem(withTitle: "Replay rank reveal", action: #selector(replay), keyEquivalent: "")
        m.addItem(withTitle: "Run setup again", action: #selector(setupAgain), keyEquivalent: "")
        m.addItem(withTitle: "Rescan all history", action: #selector(backfill), keyEquivalent: "")
        m.addItem(withTitle: "Sync remote machines", action: #selector(sync), keyEquivalent: "")
        m.addItem(.separator())
        m.addItem(withTitle: "Copy share card", action: #selector(copyCard), keyEquivalent: "c")
        m.addItem(withTitle: "Save share card to Desktop", action: #selector(saveCard), keyEquivalent: "")
        m.addItem(withTitle: "Copy full stats image", action: #selector(copyImage), keyEquivalent: "")
        m.addItem(.separator())
        m.addItem(withTitle: "Open data folder", action: #selector(openData), keyEquivalent: "")
        m.addItem(withTitle: "Open emblems folder", action: #selector(openEmblems), keyEquivalent: "")
        m.addItem(.separator())
        m.addItem(withTitle: "Quit Tierminal", action: #selector(quit), keyEquivalent: "q")
        m.items.forEach { $0.target = self }
        item.menu = m
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func refresh() { store.refresh() }
    @objc private func replay() { if let s = store.stats { showReveal(from: nil, to: s) } }
    @objc private func setupAgain() {
        store.exec(["setup", "status"]) { [weak self] out in
            let st = (try? JSONDecoder().decode(SetupStatus.self, from: Data(out.utf8)))
                ?? SetupStatus(shell: false, claude: false, claudeInstalled: false, commands: 0)
            self?.showSetup(st, step: 1)
        }
    }
    @objc private func backfill() { store.backfill() }
    @objc private func sync() { store.sync() }
    @objc private func copyCard() { if let s = store.stats { Share.copy(s) } }
    @objc private func saveCard() { if let s = store.stats { _ = Share.save(s) } }
    @objc private func openData() { NSWorkspace.shared.open(EmblemImages.dir.deletingLastPathComponent()) }
    @objc private func openEmblems() {
        try? FileManager.default.createDirectory(at: EmblemImages.dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(EmblemImages.dir)
    }
    @objc private func copyImage() {
        guard let s = store.stats, let img = MainActor.assumeIsolated({ DashboardContent.render(s, store: store) }) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([img])
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
