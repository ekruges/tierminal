<p align="center"><img src="banner.png" alt="Tierminal" width="900"></p>

Menu bar app for macOS that ranks every shell command you and your AI agents run. Ten tiers from Iron to
Root, XP from commands, ssh time and monitoring time, a rank reveal, share cards.

## Install

Download `Tierminal-<version>.zip` from Releases, unzip, move to Applications, open. The build is not
notarized: right-click, Open on first launch. The setup wizard installs the hooks and imports your history.

From source, with the Xcode command line tools:

```bash
./install.sh
```

## What is counted

- Every interactive zsh or bash command, with timing and exit code.
- Every command an AI agent runs through a shell. Claude Code has exact hooks; everything else is matched by its
  process tree against a registry of about 55 agents, with provider and model attribution. See [AGENTS.md](AGENTS.md).
- History: zsh, Amazon Q, Claude Code transcripts, Codex rollouts, re-read for new entries every 90 seconds.
- Other machines over ssh: `tierminal.py remote add <host>`.

Only command text, timing and the names of agent env vars are recorded. Nothing leaves the machine.

## Ranks

| Tier | XP | | Tier | XP |
|------|----|-|------|----|
| Iron | 0 | | Diamond | 15,000 |
| Bronze | 100 | | Ascendant | 30,000 |
| Silver | 500 | | Immortal | 60,000 |
| Gold | 2,000 | | Radiant | 120,000 |
| Platinum | 6,000 | | Root | 200,000 |

Three divisions per tier, Root has none. XP is one point per command plus one per minute inside ssh or a
monitoring tool, so a hundred commands a day reaches Gold in three weeks and Diamond in five months; agents running
hundreds a day get to Root within a year. Drop your own art into `~/Library/Application Support/Tierminal/emblems/`
as `gold-3.png`, `root.png` and so on to replace the bundled set.

MIT license.
