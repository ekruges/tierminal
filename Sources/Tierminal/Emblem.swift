import AppKit
import SwiftUI

enum EmblemImages {
    static let dir = URL(fileURLWithPath: NSString(string: "~/Library/Application Support/Tierminal/emblems").expandingTildeInPath)
    private static var cache: [String: NSImage?] = [:]

    static func name(tier: Int, division: Int) -> String {
        tier >= Tier.names.count - 1 ? "root" : "\(Tier.names[max(0, tier)].lowercased())-\(max(1, division))"
    }

    static func image(tier: Int, division: Int) -> NSImage? {
        let n = name(tier: tier, division: division)
        if let hit = cache[n] { return hit }
        let img = NSImage(contentsOf: dir.appendingPathComponent(n + ".png"))
        cache[n] = img
        return img
    }

    static func reset() { cache.removeAll() }
}

enum Brand {
    static func image(_ name: String) -> NSImage? {
        if let i = NSImage(contentsOf: EmblemImages.dir.appendingPathComponent(name + ".png")) { return i }
        return Bundle.main.resourceURL.flatMap { NSImage(contentsOf: $0.appendingPathComponent(name + ".png")) }
    }
}

struct TierShape: Shape {
    let tier: Int

    func path(in r: CGRect) -> Path {
        var p = Path()
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        func poly(_ pts: [(CGFloat, CGFloat)]) {
            p.move(to: pt(pts[0].0, pts[0].1))
            for q in pts.dropFirst() { p.addLine(to: pt(q.0, q.1)) }
            p.closeSubpath()
        }
        func ngon(_ n: Int, _ rad: CGFloat) {
            var pts: [(CGFloat, CGFloat)] = []
            for k in 0..<n {
                let a = -CGFloat.pi / 2 + CGFloat(k) * 2 * .pi / CGFloat(n)
                pts.append((0.5 + rad * cos(a), 0.5 + rad * sin(a)))
            }
            poly(pts)
        }
        func star(_ n: Int, _ ro: CGFloat, _ ri: CGFloat) {
            var pts: [(CGFloat, CGFloat)] = []
            for k in 0..<(2 * n) {
                let a = -CGFloat.pi / 2 + CGFloat(k) * .pi / CGFloat(n)
                let rad = k % 2 == 0 ? ro : ri
                pts.append((0.5 + rad * cos(a), 0.5 + rad * sin(a)))
            }
            poly(pts)
        }
        func shield(_ l: CGFloat, _ rt: CGFloat) {
            p.move(to: pt(l, 0.1))
            p.addLine(to: pt(rt, 0.1))
            p.addLine(to: pt(rt, 0.5))
            p.addQuadCurve(to: pt(0.5, 0.93), control: pt(rt, 0.82))
            p.addQuadCurve(to: pt(l, 0.5), control: pt(l, 0.82))
            p.closeSubpath()
        }

        switch tier {
        case 0:
            ngon(6, 0.46); ngon(6, 0.2)
        case 1:
            shield(0.12, 0.88)
        case 2:
            for y in [0.06, 0.44] as [CGFloat] {
                poly([(0.1, y + 0.28), (0.5, y), (0.9, y + 0.28), (0.9, y + 0.46), (0.5, y + 0.18), (0.1, y + 0.46)])
            }
        case 3:
            shield(0.28, 0.72)
            let wing: [(CGFloat, CGFloat)] = [(0.26, 0.22), (0.04, 0.12), (0.10, 0.30), (0.0, 0.30), (0.10, 0.46), (0.03, 0.50), (0.26, 0.62)]
            poly(wing)
            poly(wing.map { (1 - $0.0, $0.1) })
        case 4:
            poly([(0.5, 0.05), (0.93, 0.38), (0.77, 0.93), (0.23, 0.93), (0.07, 0.38)])
        case 5:
            poly([(0.22, 0.1), (0.78, 0.1), (0.96, 0.36), (0.5, 0.94), (0.04, 0.36)])
        case 6:
            poly([(0.5, 0.2), (0.92, 0.9), (0.08, 0.9)])
            poly([(0.5, 0.5), (0.72, 0.82), (0.28, 0.82)])
            poly([(0.5, 0.0), (0.46, 0.13), (0.54, 0.13)])
            poly([(0.28, 0.06), (0.33, 0.18), (0.40, 0.15)])
            poly([(0.72, 0.06), (0.67, 0.18), (0.60, 0.15)])
        case 7:
            poly([(0.1, 0.92), (0.1, 0.3), (0.3, 0.52), (0.5, 0.12), (0.7, 0.52), (0.9, 0.3), (0.9, 0.92)])
            poly([(0.5, 0.62), (0.6, 0.74), (0.5, 0.86), (0.4, 0.74)])
        case 8:
            star(8, 0.48, 0.22)
        default:
            star(32, 0.49, 0.455); ngon(48, 0.40)
            p.move(to: pt(0.33, 0.24)); p.addLine(to: pt(0.67, 0.24)); p.addLine(to: pt(0.67, 0.52))
            p.addQuadCurve(to: pt(0.5, 0.8), control: pt(0.67, 0.72))
            p.addQuadCurve(to: pt(0.33, 0.52), control: pt(0.33, 0.72)); p.closeSubpath()
            poly([(0.42, 0.24), (0.42, 0.14), (0.47, 0.19), (0.5, 0.1), (0.53, 0.19), (0.58, 0.14), (0.58, 0.24)])
        }
        return p
    }
}

struct FacetShape: Shape {
    let tier: Int

    func path(in r: CGRect) -> Path {
        var p = Path()
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        func line(_ pts: [(CGFloat, CGFloat)]) {
            p.move(to: pt(pts[0].0, pts[0].1))
            for q in pts.dropFirst() { p.addLine(to: pt(q.0, q.1)) }
        }
        switch tier {
        case 4:
            line([(0.5, 0.05), (0.32, 0.5), (0.23, 0.93)])
            line([(0.5, 0.05), (0.68, 0.5), (0.77, 0.93)])
            line([(0.07, 0.38), (0.32, 0.5), (0.68, 0.5), (0.93, 0.38)])
        case 5:
            line([(0.04, 0.36), (0.96, 0.36)])
            line([(0.22, 0.1), (0.36, 0.36), (0.5, 0.94)])
            line([(0.78, 0.1), (0.64, 0.36), (0.5, 0.94)])
            line([(0.5, 0.1), (0.36, 0.36)])
            line([(0.5, 0.1), (0.64, 0.36)])
        default:
            break
        }
        return p
    }
}

struct EmblemView: View {
    let tier: Int
    let division: Int
    var size: CGFloat = 80
    var animated = true
    var pips = true

    var body: some View {
        let t = Tier.at(tier)
        let custom = EmblemImages.image(tier: tier, division: division)
        VStack(spacing: 5) {
            ZStack {
                if let img = custom {
                    Image(nsImage: img).resizable().scaledToFit()
                } else {
                    TierShape(tier: tier)
                        .fill(LinearGradient(colors: [t.color2, t.color], startPoint: .top, endPoint: .bottom),
                              style: FillStyle(eoFill: true))
                    if tier == 8 && animated { Prism(size: size, colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red]) }
                    if tier == 9 && animated { Prism(size: size, colors: [.red, .black, .red, .black, .red], opacity: 0.7) }
                    TierShape(tier: tier).stroke(tier == 9 ? Color.red.opacity(0.8) : Color.black.opacity(0.35), lineWidth: 1)
                    FacetShape(tier: tier).stroke(Color.white.opacity(0.55), lineWidth: 1)
                }
                if animated { Shimmer(tier: tier, size: size, image: custom) }
            }
            .frame(width: size, height: size)
            .overlay { if animated && tier >= 6 { Orbit(color: t.color2, size: size) } }
            .modifier(Pulse(active: animated && tier >= 4))
            if pips && division > 0 { Pips(division: division, color: t.color, size: size * 0.08) }
        }
    }
}

struct Pips: View {
    let division: Int
    let color: Color
    var size: CGFloat = 8

    var body: some View {
        HStack(spacing: size * 0.5) {
            ForEach(1...3, id: \.self) { i in
                Rectangle()
                    .fill(i <= division ? color : Color.primary.opacity(0.15))
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(45))
            }
        }
    }
}

struct Shimmer: View {
    let tier: Int
    let size: CGFloat
    var image: NSImage? = nil

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.8) / 2.8
            Rectangle()
                .fill(LinearGradient(colors: [.clear, .white.opacity(0.6), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(width: size * 0.45, height: size * 1.6)
                .rotationEffect(.degrees(22))
                .offset(x: -size * 0.9 + CGFloat(t) * size * 1.8)
                .frame(width: size, height: size)
                .clipped()
                .mask {
                    if let img = image {
                        Image(nsImage: img).resizable().scaledToFit()
                    } else {
                        TierShape(tier: tier).fill(style: FillStyle(eoFill: true))
                    }
                }
        }
    }
}

struct Orbit: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
            let a = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4) / 4 * 2 * Double.pi
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    let ang = a + Double(i) * 2 * Double.pi / 3
                    Circle().fill(color).frame(width: 5, height: 5)
                        .offset(x: CGFloat(cos(ang)) * size * 0.55, y: CGFloat(sin(ang)) * size * 0.4)
                }
            }
        }
    }
}

struct Prism: View {
    let size: CGFloat
    var colors: [Color]
    var opacity: Double = 0.45

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
            let deg = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 6) / 6 * 360
            AngularGradient(colors: colors, center: .center)
                .rotationEffect(.degrees(deg))
                .opacity(opacity)
                .frame(width: size, height: size)
                .mask(TierShape(tier: colors.count > 5 ? 8 : 9).fill(style: FillStyle(eoFill: true)))
        }
    }
}

struct Pulse: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
                content.scaleEffect(1 + 0.03 * sin(ctx.date.timeIntervalSinceReferenceDate * 2))
            }
        } else {
            content
        }
    }
}

struct LadderView: View {
    let stats: Stats
    var size: CGFloat = 34

    var body: some View {
        HStack(alignment: .top, spacing: size * 0.1) {
            ForEach(0..<stats.tiers.count, id: \.self) { i in
                VStack(spacing: 3) {
                    EmblemView(tier: i, division: i == stats.tier ? stats.division : 1, size: size, animated: false, pips: false)
                        .saturation(i <= stats.tier ? 1 : 0)
                        .opacity(i <= stats.tier ? 1 : 0.4)
                        .padding(2)
                        .overlay(Rectangle().stroke(i == stats.tier ? Tier.at(i).color : .clear, lineWidth: 1))
                    Text(Fmt.short(stats.ladder[i]).replacingOccurrences(of: ".00k", with: "k").replacingOccurrences(of: ".0k", with: "k").replacingOccurrences(of: ".00M", with: "M"))
                        .font(.system(size: size * 0.24, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
