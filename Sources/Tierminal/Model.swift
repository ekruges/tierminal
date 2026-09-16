import AppKit
import SwiftUI

struct Stats: Decodable {
    let machine: String
    let total, user, claude, ai, today, week, month: Int
    let xp, xpCommands, xpSsh, xpMonitor, xpWeek, xpToday: Int
    let xpHistory: [Int]
    let etaDays: Int?
    let rankSince: String
    let tier, division: Int
    let rank: String
    let divStart: Int
    let divEnd: Int?
    let streak, longestStreak, activeDays: Int
    let sshSeconds, monitorSeconds, failRate: Double
    let sudoCount, hostsDistinct, busiestHour, charsTyped, distinctCommands, sessions: Int
    let heat: [Int]
    let heatMonths: [HeatMonth]
    let hours: [[Int]]
    let agents: [AgentStat]
    let providers: [NameCount]
    let models: [NameCount]
    let machines: [NameCount]
    let topCommands: [NameCount]
    let longest: [LongCmd]
    let sshHosts: [HostStat]
    let recent: [Recent]
    let busiestDay: DayCount?
    let since: String
    let ladder: [Int]
    let tiers: [String]
    let remotes: [String]
    let shareText: String

    struct HeatMonth: Decodable { let col: Int; let label: String }
    struct NameCount: Decodable { let name: String; let count: Int }
    struct AgentStat: Decodable { let name: String; let count: Int; let seconds: Double }
    struct LongCmd: Decodable { let cmd: String; let dur: Double; let ts: Double; let source: String }
    struct HostStat: Decodable { let host: String; let seconds: Double; let count: Int }
    struct Recent: Decodable { let cmd: String; let source: String; let ts: Double }
    struct DayCount: Decodable { let date: String; let count: Int }

    var rankKey: Int { tier * 10 + division }
    var aiShare: Double { total == 0 ? 0 : Double(ai) / Double(total) }

    var progress: Double {
        guard let end = divEnd, end > divStart else { return 1 }
        return min(1, max(0, Double(xp - divStart) / Double(end - divStart)))
    }

    var nextRank: String? {
        if division == 0 { return nil }
        if division < 3 { return "\(tiers[tier]) \(Tier.roman[division + 1])" }
        let n = tier + 1
        return n == tiers.count - 1 ? tiers[n] : "\(tiers[n]) I"
    }

    var segments: [(name: String, frac: Double, count: Int)] {
        guard total > 0 else { return [] }
        var out: [(String, Double, Int)] = [("you", Double(user) / Double(total), user)]
        var other = 0
        for a in agents where a.name != "user" {
            let f = Double(a.count) / Double(total)
            if f < 0.004 { other += a.count } else { out.append((a.name, f, a.count)) }
        }
        if other > 0 { out.append(("other", Double(other) / Double(total), other)) }
        return out.map { (name: $0.0, frac: $0.1, count: $0.2) }
    }
}

struct Tier {
    let primary: NSColor
    let secondary: NSColor
    static let roman = ["", "I", "II", "III"]
    static let names = ["Iron", "Bronze", "Silver", "Gold", "Platinum", "Diamond", "Ascendant", "Immortal", "Radiant", "Root"]

    static let all: [Tier] = [
        Tier(0x8e8e93, 0xc7c7cc),
        Tier(0xb5652d, 0xe8a877),
        Tier(0x9aa3ad, 0xe9eef3),
        Tier(0xe0a52a, 0xffe08a),
        Tier(0x2fb6ab, 0xb9f5ef),
        Tier(0x4f7be8, 0xb6cbff),
        Tier(0x2fb455, 0xb4f5c5),
        Tier(0xd9315f, 0xff9ec0),
        Tier(0xf2f2f2, 0xffd54a),
        Tier(0xd90429, 0x2a0a12),
    ]

    static func at(_ i: Int) -> Tier { all[max(0, min(all.count - 1, i))] }

    init(_ p: UInt32, _ s: UInt32) {
        primary = NSColor(hex: p)
        secondary = NSColor(hex: s)
    }

    var color: Color { Color(nsColor: primary) }
    var color2: Color { Color(nsColor: secondary) }
}

enum AgentColors {
    static let table: [String: UInt32] = [
        "claude": 0xd97757, "codex": 0x10a37f, "gemini": 0x4285f4, "grok": 0xb0b0b0, "hermes": 0x8b5cf6,
        "deepseek": 0x4d6bfe, "ollama": 0x9aa0a6, "copilot": 0x6e40c9, "cursor": 0x3b82f6, "amazonq": 0xff9900,
        "aider": 0x22c55e, "opencode": 0xf59e0b, "goose": 0xec4899, "cline": 0x14b8a6, "qwen": 0x6366f1,
        "kimi": 0x0ea5e9, "kiro": 0xa855f7, "windsurf": 0x06b6d4, "other": 0x7a7a7a,
    ]
    static func color(_ name: String, you: Color) -> Color {
        name == "you" ? you : Color(nsColor: NSColor(hex: table[name] ?? 0x7a7a7a))
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
                  green: CGFloat((hex >> 8) & 0xff) / 255,
                  blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
}

extension NSImage {
    var png: Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

enum Fmt {
    static func num(_ n: Int) -> String { n.formatted(.number) }

    static func short(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.2fM", Double(n) / 1e6) }
        if n >= 10_000 { return String(format: "%.1fk", Double(n) / 1e3) }
        if n >= 1_000 { return String(format: "%.2fk", Double(n) / 1e3) }
        return "\(n)"
    }

    static func dur(_ secs: Double) -> String {
        let s = Int(secs.rounded())
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m \(s % 60)s" }
        if s < 86400 { return "\(s / 3600)h \((s % 3600) / 60)m" }
        return "\(s / 86400)d \((s % 86400) / 3600)h"
    }

    static func ago(_ ts: Double) -> String {
        let d = Date().timeIntervalSince1970 - ts
        if d < 60 { return "now" }
        if d < 3600 { return "\(Int(d / 60))m" }
        if d < 86400 { return "\(Int(d / 3600))h" }
        return "\(Int(d / 86400))d"
    }

    static func pct(_ x: Double) -> String { String(format: "%.1f%%", x * 100) }

    static func hours(_ secs: Double) -> String {
        let h = Int(secs / 3600)
        return h == 0 ? "<1h" : "\(h)h"
    }
}
