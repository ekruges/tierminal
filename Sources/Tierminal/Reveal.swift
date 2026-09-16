import AppKit
import SwiftUI

struct Snapshot {
    var total: Int
    var xp: Int
    var rankKey: Int
}

struct RevealPlan {
    let from: Snapshot?
    let to: Stats
    let steps: [(tier: Int, division: Int)]

    init(from: Snapshot?, to: Stats) {
        self.from = from
        self.to = to
        var all: [(Int, Int)] = []
        for t in 0..<(Tier.names.count - 1) { for d in 1...3 { all.append((t, d)) } }
        all.append((Tier.names.count - 1, 0))
        let key = { (r: (Int, Int)) in r.0 * 10 + r.1 }
        let s = all.firstIndex { key($0) == (from?.rankKey ?? 1) } ?? 0
        let e = all.firstIndex { key($0) == to.rankKey } ?? s
        steps = all[s...max(s, e)].map { (tier: $0.0, division: $0.1) }
    }

    var stepDur: Double { min(0.9, max(0.45, 4.5 / Double(steps.count))) }
    var tA: Double { 2.4 }
    var tB: Double { tA + Double(steps.count) * stepDur }
    var tEnd: Double { tB + 0.6 }
}

struct RevealView: View {
    let plan: RevealPlan
    var fixedTime: Double? = nil
    var onDone: () -> Void = {}
    @State private var start = Date()

    var body: some View {
        Group {
            if let ft = fixedTime {
                content(ft)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 60)) { ctx in content(ctx.date.timeIntervalSince(start)) }
            }
        }
        .frame(width: 620, height: 720)
        .background(RoundedRectangle(cornerRadius: 24).fill(Color(nsColor: NSColor(hex: 0x141416))))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .environment(\.colorScheme, .dark)
    }

    func ease(_ x: Double) -> Double {
        let c = min(1, max(0, x))
        return 1 - pow(1 - c, 3)
    }

    func lerp(_ a: Int, _ b: Int, _ p: Double) -> Int { a + Int((Double(b - a) * p).rounded()) }

    func name(_ r: (tier: Int, division: Int)) -> String {
        r.division == 0 ? Tier.names[r.tier] : "\(Tier.names[r.tier]) \(Tier.roman[r.division])"
    }

    func content(_ t: Double) -> some View {
        let s = plan.to
        let pA = ease(t / plan.tA)
        let inB = t >= plan.tA
        let done = t >= plan.tEnd
        return VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text(Fmt.num(lerp(plan.from?.total ?? 0, s.total, pA)))
                    .font(.system(size: 88, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white)
                    .contentTransition(.identity)
                Text("commands").font(.system(size: 15)).foregroundStyle(Color.white.opacity(0.5))
                HStack(spacing: 26) {
                    stat(t, at: 0.5, Fmt.num(lerp(0, s.activeDays, pA)), "active days")
                    stat(t, at: 0.8, "\(lerp(0, s.streak, pA))d", "streak")
                    stat(t, at: 1.1, Fmt.dur(Double(lerp(0, Int(s.sshSeconds), pA))), "in ssh")
                    stat(t, at: 1.4, "\(lerp(0, Int((s.aiShare * 100).rounded()), pA))%", "run by AI")
                    stat(t, at: 1.7, Fmt.short(lerp(0, s.charsTyped, pA)), "chars typed")
                }
                .padding(.top, 10)
            }
            .scaleEffect(inB ? 0.55 : 1, anchor: .top)
            .padding(.top, inB ? 26 : 210)
            .animation(.easeInOut(duration: 0.6), value: inB)
            Spacer(minLength: 0)
            if inB {
                dial(t - plan.tA)
                    .transition(.opacity)
                    .padding(.bottom, done ? 0 : 60)
            }
            if done {
                footer.transition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .animation(.easeInOut(duration: 0.4), value: done)
    }

    func stat(_ t: Double, at: Double, _ v: String, _ l: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.system(size: 20, weight: .bold, design: .monospaced)).foregroundStyle(.white)
            Text(l).font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.5))
        }
        .opacity(ease((t - at) / 0.4))
        .offset(y: 10 * (1 - ease((t - at) / 0.4)))
    }

    func dial(_ tb: Double) -> some View {
        let n = plan.steps.count
        let k = min(n - 1, Int(tb / plan.stepDur))
        let local = min(1, (tb - Double(k) * plan.stepDur) / plan.stepDur)
        let finished = tb >= Double(n) * plan.stepDur
        let cur = plan.steps[k]
        let color = Tier.at(cur.tier).color
        return VStack(spacing: 18) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.08), lineWidth: 16)
                if k > 0 && local < 0.35 {
                    Circle().stroke(Tier.at(plan.steps[k - 1].tier).color, lineWidth: 16)
                        .opacity(Double(1 - local / 0.35))
                }
                Circle().trim(from: 0, to: CGFloat(finished ? 1 : local))
                    .stroke(color, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if k > 0 && local < 0.6 {
                    let prev = plan.steps[k - 1]
                    Shatter(tier: prev.tier, division: prev.division, size: 170, p: ease(local / 0.6))
                }
                EmblemView(tier: cur.tier, division: cur.division, size: 170, animated: finished, pips: true)
                    .scaleEffect(local < 0.3 ? 0.8 + 0.2 * ease(local / 0.3) : 1)
                    .opacity(local < 0.15 ? ease(local / 0.15) : 1)
            }
            .frame(width: 316, height: 316)
            Text(name(cur)).font(.system(size: 34, weight: .bold)).foregroundStyle(.white)
            Text("\(Fmt.num(lerp(plan.from?.xp ?? 0, plan.to.xp, min(1, tb / (Double(n) * plan.stepDur))))) XP")
                .font(.system(size: 16, design: .monospaced)).foregroundStyle(Color.white.opacity(0.6))
        }
    }

    var footer: some View {
        VStack(spacing: 10) {
            if let f = plan.from {
                Text("+\(Fmt.num(plan.to.total - f.total)) commands · +\(Fmt.num(plan.to.xp - f.xp)) XP since you last looked")
                    .font(.system(size: 13, design: .monospaced)).foregroundStyle(Color.white.opacity(0.6))
            }
            Button(action: onDone) {
                Text("Continue").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 7)
                    .overlay(Rectangle().stroke(Color.white.opacity(0.5), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.top, 18)
    }
}

struct Shatter: View {
    let tier: Int
    let division: Int
    let size: CGFloat
    let p: Double

    var body: some View {
        ZStack {
            ForEach(0..<12, id: \.self) { i in
                let a = (Double(i) + 0.5) / 12 * 2 * Double.pi
                EmblemView(tier: tier, division: division, size: size, animated: false, pips: false)
                    .mask(Wedge(index: i, count: 12))
                    .offset(x: CGFloat(cos(a) * p) * size * 0.9,
                            y: CGFloat(sin(a) * p) * size * 0.9 + CGFloat(p * p) * size * 0.35)
                    .rotationEffect(.degrees((i % 2 == 0 ? 1 : -1) * 70 * p))
                    .opacity(1 - p)
            }
        }
        .frame(width: size, height: size)
    }
}

struct Wedge: Shape {
    let index: Int
    let count: Int

    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY)
        p.move(to: c)
        p.addArc(center: c, radius: r.width, startAngle: .degrees(Double(index) / Double(count) * 360),
                 endAngle: .degrees(Double(index + 1) / Double(count) * 360), clockwise: false)
        p.closeSubpath()
        return p
    }
}

final class RevealWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}
