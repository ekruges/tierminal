import AppKit
import SwiftUI

struct SetupStatus: Decodable {
    let shell: Bool
    let claude: Bool
    let claudeInstalled: Bool
    let commands: Int

    var complete: Bool { shell && (claude || !claudeInstalled) }
}

struct SetupView: View {
    @ObservedObject var store: StatsStore
    let status: SetupStatus
    var done: () -> Void = {}
    var startStep = 0
    @State private var step = 0
    @State private var shell = false
    @State private var claude = false
    @State private var busy = false
    @State private var imported = ""
    @State private var started = false

    private let pages = 6

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                page.id(step)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            HStack(spacing: 6) {
                ForEach(0..<pages, id: \.self) { i in
                    Rectangle().fill(i == step ? Color.white : Color.white.opacity(0.2)).frame(width: i == step ? 18 : 6, height: 4)
                        .animation(.easeInOut(duration: 0.3), value: step)
                }
            }
            .padding(.bottom, 18)
        }
        .frame(width: 520, height: 560)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color(nsColor: NSColor(hex: 0x141416))))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .environment(\.colorScheme, .dark)
        .onAppear {
            if !started {
                started = true
                step = startStep
                shell = status.shell
                claude = status.claude
            }
        }
    }

    @ViewBuilder var page: some View {
        switch step {
        case 0: welcome
        case 1: shellPage
        case 2: claudePage
        case 3: importPage
        case 4: menuBarPage
        default: finish
        }
    }

    func next() { withAnimation(.easeInOut(duration: 0.35)) { step += 1 } }

    var welcome: some View {
        VStack(spacing: 18) {
            Spacer()
            if let l = Brand.image("logo") {
                Image(nsImage: l).resizable().scaledToFit().frame(width: 200, height: 200)
            } else {
                EmblemView(tier: Tier.names.count - 1, division: 0, size: 170, animated: true, pips: false)
            }
            if let w = Brand.image("wordmark") {
                Image(nsImage: w).resizable().scaledToFit().frame(width: 400)
            } else {
                Text("Tierminal").font(.system(size: 34, weight: .bold)).foregroundStyle(.white)
            }
            Text("Every command you and your AI agents run, ranked.")
                .font(.system(size: 14)).foregroundStyle(Color.white.opacity(0.6))
            Spacer()
            primary("Set up", action: next)
        }
        .padding(30)
    }

    var shellPage: some View {
        stepPage(title: "Track your shell",
                 body: "Adds one line each to ~/.zshenv, ~/.bashrc and ~/.profile. Every command you type, and every command an agent runs through a shell, is counted. Only the command text, timing, exit code and the names of agent env vars are recorded, never their values.",
                 installed: shell, label: "Install shell hooks") {
            busy = true
            store.exec(["setup", "shell"]) { _ in busy = false; withAnimation { shell = true } }
        }
    }

    var claudePage: some View {
        Group {
            if status.claudeInstalled {
                stepPage(title: "Track Claude Code",
                         body: "Adds PreToolUse and PostToolUse hooks for the Bash tool to ~/.claude/settings.json, so Claude's commands carry exact timing and the model name.",
                         installed: claude, label: "Install Claude hooks") {
                    busy = true
                    store.exec(["setup", "claude"]) { _ in busy = false; withAnimation { claude = true } }
                }
            } else {
                stepPage(title: "Claude Code",
                         body: "Claude Code was not found on this Mac. If you install it later, the shell hooks still catch its commands; run Setup again from the menu for exact timing.",
                         installed: true, label: "", action: {})
            }
        }
    }

    var importPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import history").font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
            Text("Reads ~/.zsh_history, Amazon Q's shell history, every Claude Code transcript and every Codex rollout on this Mac. Nothing leaves the machine.")
                .font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.65)).fixedSize(horizontal: false, vertical: true)
            if !imported.isEmpty {
                Text(imported).font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.white.opacity(0.8))
            } else if busy {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("importing").font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.6)) }
            } else {
                secondary("Import", action: {
                    busy = true
                    store.exec(["backfill"]) { out in busy = false; withAnimation { imported = out.trimmingCharacters(in: .whitespacesAndNewlines) } }
                })
            }
            Spacer()
            HStack { Spacer(); primary(imported.isEmpty ? "Skip" : "Next", action: next) }
        }
        .padding(30)
    }

    var menuBarPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Menu bar").font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
            Text("Choose what the menu bar item shows. You can change this later in Settings.")
                .font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.65))
            MenuBarToggles(s: store.stats)
            Spacer()
            HStack { Spacer(); primary("Next", action: next) }
        }
        .padding(30)
    }

    var finish: some View {
        VStack(spacing: 18) {
            Spacer()
            Text("You're set").font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
            Text("Tierminal lives in the menu bar. Click the icon for your rank and stats, right-click for sharing and tools.")
                .font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.65)).multilineTextAlignment(.center)
            Spacer()
            primary("Show my rank", action: done)
        }
        .padding(30)
    }

    func stepPage(title: String, body: String, installed: Bool, label: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
            Text(body).font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.65)).fixedSize(horizontal: false, vertical: true)
            if installed {
                if !label.isEmpty {
                    HStack(spacing: 8) {
                        Rectangle().fill(Color.green).frame(width: 8, height: 8).rotationEffect(.degrees(45))
                        Text("Installed").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    }
                    .transition(.opacity)
                }
            } else if busy {
                ProgressView().controlSize(.small)
            } else {
                secondary(label, action: action)
            }
            Spacer()
            HStack { Spacer(); primary(installed ? "Next" : "Skip", action: next) }
        }
        .padding(30)
    }

    func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.black)
                .padding(.horizontal, 20).padding(.vertical, 8).background(Color.white)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
    }

    func secondary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 7)
                .overlay(Rectangle().stroke(Color.white.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct MenuBarToggles: View {
    let s: Stats?
    @State private var tick = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(MenuBar.keys, id: \.key) { k in
                Toggle(k.label, isOn: Binding(
                    get: { MenuBar.on(k.key) },
                    set: { UserDefaults.standard.set($0, forKey: k.key); tick += 1 }))
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            if let s {
                HStack(spacing: 6) {
                    if MenuBar.showEmblem { EmblemView(tier: s.tier, division: s.division, size: 18, animated: false, pips: false) }
                    let t = MenuBar.title(s)
                    Text(t.isEmpty && !MenuBar.showEmblem ? "(empty: emblem stays on)" : t).font(.system(size: 13, weight: .medium))
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .overlay(Rectangle().stroke(Color.primary.opacity(0.2), lineWidth: 1))
                .padding(.top, 6)
                .id(tick)
            }
        }
    }
}
