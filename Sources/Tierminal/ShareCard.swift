import AppKit
import SwiftUI

struct ShareCard: View {
    let s: Stats

    var body: some View {
        let t = Tier.at(s.tier)
        HStack(spacing: 0) {
            VStack(spacing: 14) {
                Spacer(minLength: 0)
                EmblemView(tier: s.tier, division: s.division, size: 250, animated: false)
                Text(s.rank).font(.system(size: 48, weight: .bold)).foregroundStyle(.white)
                Text("\(Fmt.short(s.xp)) XP").font(.system(size: 24, design: .monospaced)).foregroundStyle(Color.white.opacity(0.7))
                VStack(spacing: 8) {
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.white.opacity(0.12))
                        Rectangle().fill(t.color).frame(width: 260 * s.progress)
                    }
                    .frame(width: 260, height: 6)
                    Text(s.nextRank.map { "\(Int((s.progress * 100).rounded()))% to \($0)" } ?? "top of the ladder")
                        .font(.system(size: 14)).foregroundStyle(Color.white.opacity(0.5))
                }
                Spacer(minLength: 0)
            }
            .frame(width: 440)
            VStack(alignment: .leading, spacing: 26) {
                HStack {
                    if let w = Brand.image("wordmark") {
                        Image(nsImage: w).resizable().scaledToFit().frame(height: 62)
                    } else {
                        Text("TIERMINAL").font(.system(size: 14, weight: .bold)).kerning(4).foregroundStyle(t.color)
                    }
                    Spacer()
                    Text("since \(s.since)").font(.system(size: 14)).foregroundStyle(Color.white.opacity(0.4))
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .leading), count: 3), spacing: 20) {
                    big(Fmt.short(s.total), "commands")
                    big("\(s.streak)d", "streak")
                    big(Fmt.hours(s.sshSeconds), "in ssh")
                    big(Fmt.short(s.activeDays), "active days")
                    big("\(Int((s.aiShare * 100).rounded()))%", "run by AI")
                    big("+\(Fmt.short(s.xpWeek))", "XP this week")
                }
                VStack(alignment: .leading, spacing: 8) {
                    SplitBar(s: s, height: 14, animate: false)
                    Legend(s: s, font: 15)
                }
                YearHeatmap(heat: s.heat, months: s.heatMonths, color: t.color, cell: 10, gap: 2.5)
                LadderView(stats: s, size: 46)
                Spacer(minLength: 0)
            }
            .frame(width: 700, alignment: .leading)
            .padding(.top, 46)
            .padding(.trailing, 40)
        }
        .frame(width: 1200, height: 675, alignment: .topLeading)
        .background(Color(nsColor: NSColor(hex: 0x141416)))
        .overlay(Rectangle().stroke(t.color.opacity(0.35), lineWidth: 3))
        .environment(\.colorScheme, .dark)
    }

    func big(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(v).font(.system(size: 40, weight: .bold, design: .monospaced)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
            Text(l).font(.system(size: 15)).foregroundStyle(Color.white.opacity(0.5))
        }
    }
}

struct SplitBar: View {
    let s: Stats
    var height: CGFloat = 8
    var animate = true
    @State private var grow = false

    var body: some View {
        let you = Tier.at(s.tier).color
        GeometryReader { g in
            HStack(spacing: 1) {
                ForEach(Array(s.segments.enumerated()), id: \.offset) { e in
                    Rectangle().fill(AgentColors.color(e.element.name, you: you))
                        .frame(width: max(1, g.size.width * e.element.frac * (grow || !animate ? 1 : 0.02)))
                }
                if animate && !grow { Spacer(minLength: 0) }
            }
        }
        .frame(height: height)
        .onAppear { withAnimation(.easeOut(duration: 0.9)) { grow = true } }
    }
}

struct Legend: View {
    let s: Stats
    var font: CGFloat = 11

    var body: some View {
        let you = Tier.at(s.tier).color
        HStack(spacing: 12) {
            ForEach(Array(s.segments.prefix(6).enumerated()), id: \.offset) { e in
                HStack(spacing: 4) {
                    Rectangle().fill(AgentColors.color(e.element.name, you: you)).frame(width: font * 0.7, height: font * 0.7)
                    Text("\(e.element.name) \(Int((e.element.frac * 100).rounded()))%")
                        .font(.system(size: font, design: .monospaced))
                }
            }
        }
    }
}

enum Share {
    enum Network: String { case x, bluesky, threads }

    @MainActor static func card(_ s: Stats) -> NSImage? {
        let r = ImageRenderer(content: ShareCard(s: s))
        r.scale = 2
        return r.nsImage
    }

    static func render(_ s: Stats) -> NSImage? { MainActor.assumeIsolated { card(s) } }

    @discardableResult
    static func copy(_ s: Stats) -> Bool {
        guard let img = render(s) else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([img])
        return true
    }

    static func save(_ s: Stats) -> URL? {
        guard let png = render(s)?.png else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/tierminal-\(f.string(from: Date())).png")
        return (try? png.write(to: url)) == nil ? nil : url
    }

    static func copyText(_ s: Stats) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s.shareText, forType: .string)
    }

    @discardableResult
    static func picker(_ s: Stats) -> Bool {
        guard let img = render(s), let view = NSApp.keyWindow?.contentView ?? NSApp.windows.first(where: { $0.isVisible })?.contentView else { return false }
        let picker = NSSharingServicePicker(items: [img, s.shareText])
        picker.show(relativeTo: NSRect(x: 16, y: view.bounds.height - 40, width: 1, height: 1), of: view, preferredEdge: .minY)
        return true
    }

    static func post(_ s: Stats, to n: Network) {
        copy(s)
        let q = s.shareText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let url: String
        switch n {
        case .x: url = "https://x.com/intent/post?text=\(q)"
        case .bluesky: url = "https://bsky.app/intent/compose?text=\(q)"
        case .threads: url = "https://www.threads.net/intent/post?text=\(q)"
        }
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }
}
