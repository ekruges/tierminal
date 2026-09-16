import SwiftUI

struct Dashboard: View {
    @ObservedObject var store: StatsStore
    @State private var settings = false
    @State private var ladder = false
    @AppStorage("ui.expanded") private var expanded = false

    var body: some View {
        Group {
            if let s = store.stats, settings {
                SettingsView(s: s) { withAnimation(.easeInOut(duration: 0.25)) { settings = false } }
                    .frame(width: 470, height: 700)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if let s = store.stats, ladder {
                LadderPage(s: s) { withAnimation(.easeInOut(duration: 0.25)) { ladder = false } }
                    .frame(width: 470, height: 700)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if let s = store.stats, expanded {
                ScrollView { DashboardContent(s: s, store: store, openSettings: open($settings), openLadder: open($ladder)).id(store.opens) }
                    .frame(width: 470, height: 700)
            } else if let s = store.stats {
                DashboardContent(s: s, store: store, openSettings: open($settings), openLadder: open($ladder))
                    .id(store.opens)
                    .frame(width: 470)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 8) {
                    ProgressView()
                    Text(store.error ?? "Loading stats").font(.caption).foregroundStyle(.secondary)
                }
                .frame(width: 470, height: 160)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: expanded)
        .animation(.easeInOut(duration: 0.25), value: settings)
        .animation(.easeInOut(duration: 0.25), value: ladder)
    }

    func open(_ flag: Binding<Bool>) -> () -> Void {
        { withAnimation(.easeInOut(duration: 0.25)) { flag.wrappedValue = true } }
    }
}

struct DashboardContent: View {
    let s: Stats
    @ObservedObject var store: StatsStore
    var forImage = false
    var compact: Bool? = nil
    var openSettings: () -> Void = {}
    var openLadder: () -> Void = {}
    @State private var note = ""
    @State private var hover = false
    @State private var intro = false
    @AppStorage("ui.expanded") private var expanded = false

    var t: Tier { Tier.at(s.tier) }
    var showAll: Bool { forImage ? !(compact ?? false) : expanded }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if !forImage { controls }
            headline
            VStack(alignment: .leading, spacing: 5) {
                SplitBar(s: s, height: 6, animate: !forImage)
                Legend(s: s, font: 10)
            }
            if !showAll { YearHeatmap(heat: s.heat, months: s.heatMonths, color: t.color) }
            if showAll {
            VStack(alignment: .leading, spacing: 16) {
            section("Who runs the shell") { split }
            section("XP") { xpRow }
            section("Stats") { statGrid }
            section("Last 12 months") { YearHeatmap(heat: s.heat, months: s.heatMonths, color: t.color) }
            section("Hour × weekday") { HourHeatmap(hours: s.hours, color: t.color) }
            section("Top commands") { bars(s.topCommands.map { ($0.name, $0.count) }) }
            section("Longest running") { longest }
            if !s.sshHosts.isEmpty { section("SSH hosts") { hosts } }
            if !s.providers.isEmpty { section("Providers & models") { providers } }
            if s.machines.count > 1 { section("Machines") { machines } }
            section("Recent") { recent }
            section("Ladder") { LadderView(stats: s) }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if forImage {
                Text("since \(s.since)").font(.caption).foregroundStyle(.secondary)
            } else {
                footer
            }
        }
        .padding(16)
        .frame(width: 470)
    }

    @MainActor static func render(_ s: Stats, store: StatsStore) -> NSImage? {
        let r = ImageRenderer(content: DashboardContent(s: s, store: store, forImage: true)
            .background(Color(nsColor: .windowBackgroundColor)))
        r.scale = 2
        return r.nsImage
    }

    var header: some View {
        let ring = hover || intro || forImage
        return HStack(spacing: 16) {
            VStack(spacing: 6) {
                ZStack {
                    Circle().stroke(Color.primary.opacity(ring ? 0.1 : 0), lineWidth: 7)
                    Circle().trim(from: 0, to: CGFloat(ring ? s.progress : 0))
                        .stroke(t.color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    EmblemView(tier: s.tier, division: s.division, size: 96, pips: false)
                        .scaleEffect(ring ? 0.92 : 1.12)
                }
                .frame(width: 138, height: 138)
                .contentShape(Rectangle())
                .onHover { hover = $0 }
                .onTapGesture { openLadder() }
                .animation(intro ? .easeOut(duration: 1.3) : .easeInOut(duration: 0.35), value: ring)
                .onAppear {
                    guard !forImage else { return }
                    intro = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { intro = false }
                }

                if s.division > 0 { Pips(division: s.division, color: t.color, size: 8) }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(s.rank).font(.system(size: 22, weight: .bold))
                Text("\(Fmt.num(s.xp)) XP").font(.system(size: 13, design: .monospaced)).foregroundStyle(.secondary)
                Text("\(Int((s.progress * 100).rounded()))% through \(s.rank)").font(.caption).foregroundStyle(.secondary)
                if let next = s.nextRank, let end = s.divEnd {
                    Text("\(Fmt.num(end - s.xp)) XP to \(next)" + (s.etaDays.map { " · ~\($0)d at this pace" } ?? ""))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Top of the ladder").font(.caption).foregroundStyle(.secondary)
                }
                if !s.rankSince.isEmpty {
                    Text("held since \(s.rankSince)").font(.caption).foregroundStyle(.secondary)
                }
                if showAll {
                    Text("commands \(Fmt.num(s.xpCommands)) · ssh min \(Fmt.num(s.xpSsh)) · monitor min \(Fmt.num(s.xpMonitor))")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                }
            }
        }
    }

    var controls: some View {
        HStack(spacing: 10) {
            Button(action: { withAnimation(.easeInOut(duration: 0.3)) { expanded.toggle() } }) {
                Text(expanded ? "Less" : "All stats").font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .overlay(Rectangle().stroke(Color.primary.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
            Menu {
                Button("Copy card") { note = Share.copy(s) ? "card copied" : "render failed" }
                Button("Save card to Desktop") { note = Share.save(s).map { "saved \($0.lastPathComponent)" } ?? "save failed" }
                Divider()
                Button("Post to X") { Share.post(s, to: .x); note = "card copied, paste it into the post" }
                Button("Post to Bluesky") { Share.post(s, to: .bluesky); note = "card copied, paste it into the post" }
                Button("Post to Threads") { Share.post(s, to: .threads); note = "card copied, paste it into the post" }
                Divider()
                Button("Copy text") { Share.copyText(s); note = "text copied" }
                Button("More") { note = Share.picker(s) ? "" : "render failed" }
            } label: {
                Text("Share").font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .overlay(Rectangle().stroke(Color.primary.opacity(0.3), lineWidth: 1))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            if !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary) }
        }
    }

    var headline: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .leading), count: 3), spacing: 14) {
            big(Double(s.total), "commands") { Fmt.num(Int($0)) }
            big(Double(s.today), "today") { Fmt.num(Int($0)) }
            big(Double(s.streak), "streak") { "\(Int($0))d" }
            big(s.sshSeconds, "in ssh") { Fmt.dur($0) }
            big(s.aiShare * 100, "run by AI") { "\(Int($0.rounded()))%" }
            big(Double(s.xpWeek), "XP this week") { "+" + Fmt.short(Int($0)) }
        }
    }

    func big(_ v: Double, _ l: String, _ format: @escaping (Double) -> String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            AnimatedNumber(value: v, animate: !forImage, format: format)
                .font(.system(size: 26, weight: .bold, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.6)
            Text(l).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var split: some View {
        VStack(alignment: .leading, spacing: 6) {
            SplitBar(s: s, animate: !forImage)
            ForEach(Array(s.segments.enumerated()), id: \.offset) { e in
                HStack(spacing: 8) {
                    Rectangle().fill(AgentColors.color(e.element.name, you: t.color)).frame(width: 8, height: 8)
                    Text(e.element.name).font(.system(size: 11, design: .monospaced)).frame(width: 90, alignment: .leading)
                    Text(Fmt.num(e.element.count)).font(.system(size: 11, design: .monospaced)).frame(width: 60, alignment: .trailing)
                    Text(Fmt.pct(e.element.frac)).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .trailing)
                    if let a = s.agents.first(where: { $0.name == e.element.name || ($0.name == "user" && e.element.name == "you") }) {
                        Text(Fmt.dur(a.seconds)).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    var xpRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Sparkline(values: s.xpHistory, color: t.color).frame(width: 200)
            VStack(alignment: .leading, spacing: 3) {
                Text("+\(Fmt.num(s.xpWeek)) this week").font(.system(size: 12, weight: .semibold, design: .monospaced))
                Text("+\(Fmt.num(s.xpToday)) today").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                Text("30 day trend").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
    }

    var statGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            tile(Fmt.num(s.total), "commands")
            tile(Fmt.num(s.today), "today")
            tile(Fmt.num(s.week), "7 days")
            tile("\(s.streak)d", "streak")
            tile("\(s.longestStreak)d", "best streak")
            tile("\(s.activeDays)", "active days")
            tile(Fmt.num(s.total / max(1, s.activeDays)), "per active day")
            tile(Fmt.dur(s.sshSeconds), "in ssh")
            tile(Fmt.dur(s.monitorSeconds), "monitoring")
            tile("\(s.hostsDistinct)", "ssh hosts")
            tile(Fmt.num(s.sudoCount), "sudo")
            tile(Fmt.pct(s.failRate), "failed")
            tile(Fmt.short(s.charsTyped), "chars typed by you")
            tile(Fmt.num(s.distinctCommands), "distinct commands")
            tile(Fmt.num(s.sessions), "agent sessions")
            tile(String(format: "%02d:00", s.busiestHour), "peak hour")
            if let b = s.busiestDay { tile(Fmt.num(b.count), "best day \(b.date.suffix(5))") }
            tile("\(s.machines.count)", "machines")
        }
    }

    var longest: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(s.longest.enumerated()), id: \.offset) { e in
                HStack(alignment: .top, spacing: 8) {
                    Text(Fmt.dur(e.element.dur))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .frame(width: 64, alignment: .trailing)
                    tag(e.element.source)
                    Text(e.element.cmd).font(.system(size: 11, design: .monospaced))
                        .lineLimit(1).truncationMode(.tail).foregroundStyle(.secondary)
                }
            }
        }
    }

    var hosts: some View {
        VStack(spacing: 4) {
            ForEach(Array(s.sshHosts.enumerated()), id: \.offset) { e in
                HStack {
                    Text(e.element.host).font(.system(size: 11, design: .monospaced)).lineLimit(1)
                    Spacer()
                    Text("\(e.element.count)×").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    Text(Fmt.dur(e.element.seconds)).font(.system(size: 11, design: .monospaced))
                        .frame(width: 70, alignment: .trailing)
                }
            }
        }
    }

    var providers: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(s.providers.enumerated()), id: \.offset) { e in
                HStack {
                    Text(e.element.name).font(.system(size: 11, design: .monospaced))
                    Spacer()
                    Text(Fmt.num(e.element.count)).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
            if !s.models.isEmpty {
                Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 1).padding(.vertical, 2)
                ForEach(Array(s.models.enumerated()), id: \.offset) { e in
                    HStack {
                        Text(e.element.name).font(.system(size: 11, design: .monospaced)).lineLimit(1)
                        Spacer()
                        Text(Fmt.num(e.element.count)).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    var machines: some View {
        bars(s.machines.map { ($0.name.isEmpty ? "?" : $0.name, $0.count) })
    }

    var recent: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(s.recent.enumerated()), id: \.offset) { e in
                HStack(spacing: 8) {
                    Text(Fmt.ago(e.element.ts)).font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary).frame(width: 30, alignment: .trailing)
                    tag(e.element.source)
                    Text(e.element.cmd).font(.system(size: 11, design: .monospaced)).lineLimit(1)
                }
            }
        }
    }

    var footer: some View {
        HStack(spacing: 10) {
            Text("since \(s.since)").font(.system(size: 10)).foregroundStyle(.secondary)
            Spacer()
            Button("Settings", action: openSettings)
            if !s.remotes.isEmpty { Button(store.busy ? "Syncing" : "Sync") { store.sync() }.disabled(store.busy) }
            Button(store.busy ? "Backfilling" : "Backfill") { store.backfill() }.disabled(store.busy)
            Button("Quit") { NSApp.terminate(nil) }
        }
    }

    func section<V: View>(_ title: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).kerning(0.8).foregroundStyle(.secondary)
            content()
        }
    }

    func tile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 15, weight: .semibold, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .overlay(Rectangle().stroke(Color.primary.opacity(0.12), lineWidth: 1))
    }

    func tag(_ source: String) -> some View {
        Text(source == "user" ? "you" : source)
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 4).padding(.vertical, 1)
            .overlay(Rectangle().stroke(source == "user" ? t.color : AgentColors.color(source, you: t.color), lineWidth: 1))
    }

    func bars(_ items: [(String, Int)]) -> some View {
        let m = max(1, items.map { $0.1 }.max() ?? 1)
        return VStack(spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { e in
                HStack(spacing: 8) {
                    Text(e.element.0).font(.system(size: 11, design: .monospaced)).lineLimit(1)
                        .frame(width: 120, alignment: .leading)
                    GeometryReader { g in
                        Rectangle().fill(t.color.opacity(0.8))
                            .frame(width: max(2, g.size.width * CGFloat(e.element.1) / CGFloat(m)))
                    }
                    .frame(height: 10)
                    Text(Fmt.num(e.element.1)).font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary).frame(width: 52, alignment: .trailing)
                }
            }
        }
    }
}

struct Sparkline: View {
    let values: [Int]
    let color: Color

    var body: some View {
        Canvas { g, size in
            guard values.count > 1, let lo = values.min(), let hi = values.max() else { return }
            let span = CGFloat(max(1, hi - lo))
            var p = Path()
            for (i, v) in values.enumerated() {
                let pt = CGPoint(x: size.width * CGFloat(i) / CGFloat(values.count - 1),
                                 y: size.height - 1 - (size.height - 2) * CGFloat(v - lo) / span)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            g.stroke(p, with: .color(color), lineWidth: 1.5)
        }
        .frame(height: 36)
    }
}

enum Heat {
    static func level(_ v: Int, _ m: Int, _ c: Color) -> Color {
        v == 0 ? Color.primary.opacity(0.07) : c.opacity(0.2 + 0.8 * (min(1, Double(v) / Double(m))).squareRoot())
    }
}

struct YearHeatmap: View {
    let heat: [Int]
    let months: [Stats.HeatMonth]
    let color: Color
    var cell: CGFloat = 6
    var gap: CGFloat = 1.5

    var body: some View {
        let cols = (heat.count + 6) / 7
        let m = max(1, heat.max() ?? 1)
        VStack(alignment: .leading, spacing: 3) {
            ZStack(alignment: .topLeading) {
                ForEach(months, id: \.col) { mo in
                    Text(mo.label).font(.system(size: cell * 1.5)).foregroundStyle(.secondary)
                        .offset(x: CGFloat(mo.col) * (cell + gap))
                }
            }
            .frame(height: cell * 1.9, alignment: .topLeading)
            Canvas { g, _ in
                for (i, v) in heat.enumerated() {
                    let r = CGRect(x: CGFloat(i / 7) * (cell + gap), y: CGFloat(i % 7) * (cell + gap), width: cell, height: cell)
                    g.fill(Path(roundedRect: r, cornerRadius: 1), with: .color(Heat.level(v, m, color)))
                }
            }
            .frame(width: CGFloat(cols) * (cell + gap), height: 7 * (cell + gap))
        }
    }
}

struct HourHeatmap: View {
    let hours: [[Int]]
    let color: Color
    private let cell: CGFloat = 13.5
    private let gap: CGFloat = 1.5
    private let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        let m = max(1, hours.flatMap { $0 }.max() ?? 1)
        HStack(alignment: .top, spacing: 4) {
            VStack(spacing: gap) {
                ForEach(days, id: \.self) { d in
                    Text(d).font(.system(size: 9)).foregroundStyle(.secondary).frame(height: cell)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Canvas { g, _ in
                    for w in 0..<min(7, hours.count) {
                        for h in 0..<min(24, hours[w].count) {
                            let r = CGRect(x: CGFloat(h) * (cell + gap), y: CGFloat(w) * (cell + gap), width: cell, height: cell)
                            g.fill(Path(roundedRect: r, cornerRadius: 1), with: .color(Heat.level(hours[w][h], m, color)))
                        }
                    }
                }
                .frame(width: 24 * (cell + gap), height: 7 * (cell + gap))
                HStack(spacing: 0) {
                    ForEach([0, 6, 12, 18], id: \.self) { h in
                        Text(String(format: "%02d", h)).font(.system(size: 9)).foregroundStyle(.secondary)
                            .frame(width: 6 * (cell + gap), alignment: .leading)
                    }
                }
            }
        }
    }
}

struct LadderPage: View {
    let s: Stats
    var done: () -> Void = {}
    var scroll = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("TIERS").font(.system(size: 10, weight: .semibold)).kerning(0.8).foregroundStyle(.secondary)
                Spacer()
                Button("Done", action: done)
            }
            let rows = VStack(spacing: 8) {
                ForEach((0..<s.tiers.count).reversed(), id: \.self) { i in row(i) }
            }
            if scroll { ScrollView { rows } } else { rows }
        }
        .padding(16)
    }

    func row(_ i: Int) -> some View {
        let t = Tier.at(i)
        let base = s.ladder[i]
        let next = i + 1 < s.ladder.count ? s.ladder[i + 1] : nil
        let reached = s.tier > i
        let current = s.tier == i
        let range = next.map { "\(Fmt.num(base)) to \(Fmt.num($0)) XP" } ?? "\(Fmt.num(base)) XP and up"
        let status: String = current ? "current · \(Int((s.progress * 100).rounded()))% through \(s.rank)"
            : reached ? "reached" : "\(Fmt.num(base - s.xp)) XP away"
        return HStack(spacing: 14) {
            HStack(spacing: 6) {
                if i == s.tiers.count - 1 {
                    EmblemView(tier: i, division: 0, size: 48, animated: false, pips: false)
                        .saturation(reached || current ? 1 : 0)
                        .opacity(reached || current ? 1 : 0.4)
                } else {
                    ForEach(1...3, id: \.self) { d in
                        let unlocked = reached || (current && d <= s.division)
                        EmblemView(tier: i, division: d, size: 48, animated: false, pips: false)
                            .padding(2)
                            .overlay(Rectangle().stroke(current && d == s.division ? t.color : .clear, lineWidth: 1))
                            .saturation(unlocked ? 1 : 0)
                            .opacity(unlocked ? 1 : 0.4)
                    }
                }
            }
            .frame(width: 174, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(s.tiers[i]).font(.system(size: 15, weight: .bold)).foregroundStyle(current ? t.color : .primary)
                Text(range).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                Text(status).font(.system(size: 11)).foregroundStyle(current ? t.color : .secondary)
            }
            Spacer()
        }
        .padding(8)
        .overlay(Rectangle().stroke(current ? t.color : Color.primary.opacity(0.12), lineWidth: 1))
    }
}

struct AnimatedNumber: View {
    let value: Double
    var animate = true
    let format: (Double) -> String
    @State private var shown = 0.0

    var body: some View {
        Text("").modifier(Counter(value: animate ? shown : value, format: format))
            .onAppear { withAnimation(.easeOut(duration: 1.1)) { shown = value } }
            .onChange(of: value) { _, v in withAnimation(.easeOut(duration: 0.8)) { shown = v } }
    }
}

struct Counter: ViewModifier, Animatable {
    var value: Double
    let format: (Double) -> String
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }
    func body(content: Content) -> some View { Text(format(value)) }
}
