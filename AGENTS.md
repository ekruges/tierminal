# Agents and providers

How Tierminal knows who ran a command. Researched 2026-09-15; sources at the bottom.

## Capture paths

1. **Claude Code, local**: PreToolUse/PostToolUse hooks on the Bash tool. Exact command, duration, exit code,
   model name from the transcript.
2. **Every other agent**: the shell hooks in `~/.zshenv`, `~/.bashrc`, `~/.profile` and `BASH_ENV`. A shell
   started with `-c` logs its command string plus up to eight ancestor process command lines plus the *names*
   of env vars matching `*_API_KEY`, `*_MODEL`, `CLAUDECODE`, `CLAUDE_CODE_*`, `GEMINI_CLI`, `CODEX_SANDBOX*`,
   `CURSOR_AGENT`, `OLLAMA_*`, `HF_TOKEN`, `AGY_*`. Values are never written, except `*_MODEL` values. Ingest
   matches markers first, then ancestors against the registry.
3. **Remote machines**: the same hooks under `~/.local/share/tierminal`, pulled over ssh.

Not caught: agents that spawn `/bin/sh -c` (POSIX sh reads no startup file). Node's `child_process.exec`
does this by default; agents that use `bash -c`, `bash -lc`, `zsh -c` or the user's `$SHELL` are caught.

## Verified subprocess markers

| Agent | Env var set for its subprocesses | Source |
|-------|----------------------------------|--------|
| Claude Code | `CLAUDECODE=1`, `CLAUDE_CODE_ENTRYPOINT` | observed locally |
| Gemini CLI | `GEMINI_CLI=1` | gemini-cli docs, tools/shell.md |
| Codex CLI | `CODEX_SANDBOX=seatbelt` (macOS), `CODEX_SANDBOX_NETWORK_DISABLED` | codex sandbox analysis |
| Cursor CLI | `CURSOR_AGENT` | cursor.com docs, agent/tools/terminal |

Only these are mapped directly to an agent. User config vars such as `CODEX_HOME`, `COPILOT_HOME`, `GROK_HOME`,
`AMP_DATA_HOME`, `OPENCODE_DATA_DIR` are deliberately not used: exported globally they would tag every shell.

## Registry

| Agent | Binary / package | Vendor | Default provider | Data on disk | Backfill |
|-------|------------------|--------|------------------|--------------|----------|
| claude | `claude`, `@anthropic-ai/claude-code`, Claw Code fork | Anthropic | anthropic | `~/.claude/projects/**/*.jsonl` | yes |
| codex | `codex`, `@openai/codex`, Codex.app | OpenAI | openai | `~/.codex/sessions/**/rollout-*.jsonl` | yes |
| gemini | `gemini`, `@google/gemini-cli` | Google | google | `~/.gemini/tmp/<hash>/chats/*.json` | no |
| antigravity | `agy` (CLI), Antigravity.app (IDE) | Google | google | `~/.gemini/antigravity-cli/` | no |
| jules | `jules` | Google | google | | no |
| grok | `grok` (Grok Build), `grok-cli` (superagent) | xAI | xai | `~/.grok/` (`GROK_HOME`) | no |
| hermes | `hermes`, hermes-agent | Nous Research | nous | `~/.hermes/` (sessions, checkpoints, profiles) | no |
| opencode | `opencode`, opencode-ai | Anomaly | multi | `~/.local/share/opencode/storage/{session,message}` | no |
| pi | `pi`, pi-mono | Armin Ronacher | multi | | no |
| openhands | `openhands` | All Hands | multi | | no |
| aider | `aider` | Aider | multi | `.aider.chat.history.md` per repo | no |
| goose | `goose` | Block | multi | `~/.local/share/goose/` | no |
| cline / roo / kilo | `cline`, `roo`, `kilo` | | multi | VS Code globalStorage | no |
| continue | `cn` | Continue | multi | | no |
| crush | `crush` | Charm | multi | | no |
| qwen | `qwen`, `@qwen-code/qwen-code` | Alibaba | alibaba | `~/.qwen/` | no |
| kimi | `kimi`, kimi-cli, kimi-code | Moonshot | moonshot | `~/.kimi/sessions/<md5 of cwd>/<id>` | no |
| mimo | `mimo`, mimo-code | Xiaomi | xiaomi | | no |
| trae | `trae`, trae-agent, Trae.app | ByteDance | bytedance | | no |
| vibe | `vibe`, mistral-vibe | Mistral | mistral | | no |
| groq | groq-code-cli | Groq | groq | | no |
| neovate | neovate-code | Ant Group | ant | | no |
| deepseek | anything with deepseek in the path | DeepSeek | deepseek | | no |
| ollama | `ollama` | Ollama | ollama | | no |
| amazonq | `q` in `~/.local/bin`, `qchat` | AWS | amazon | `~/Library/Application Support/amazon-q/data.sqlite3` | yes (shell history) |
| kiro | `kiro`, kiro-cli, Kiro.app | AWS | amazon | | no |
| copilot | `copilot`, `@github/copilot` | GitHub | github | `~/.copilot/` (`COPILOT_HOME`), `COPILOT_MODEL` | no |
| cursor | `cursor-agent`, Cursor.app | Cursor | multi | `~/.cursor/` | no |
| windsurf | Windsurf.app | Codeium | multi | | no |
| warp | Warp.app (agent mode) | Warp | multi | | no |
| zed | Zed.app (agent panel) | Zed | multi | | no |
| auggie | `auggie`, `@augmentcode/auggie` | Augment | multi | | no |
| droid | `droid` | Factory | multi | `~/.factory/sessions/`, `.factory/sessions/` | no |
| amp | `amp`, `@sourcegraph/amp` | Sourcegraph | multi | `~/.config/amp/settings.json`, `AMP_DATA_HOME` | no |
| junie | `junie` | JetBrains | jetbrains | | no |
| cortex | cortex-code | Snowflake | snowflake | | no |
| devin | `devin` | Cognition | cognition | | no |
| rovodev | `acli rovodev` | Atlassian | atlassian | | no |
| tabnine, codebuff, plandex, letta, deepagents, swe-agent, interpreter, gptme, ra-aid, kode, nanocoder, prime | same as name | various | multi | | no |
| openclaw | `openclaw`, nanobot, zeroclaw, picoclaw, ironclaw, nullclaw | various | multi | | no |

"Backfill" means a transcript importer exists in `tierminal.py`. Importers were only written for formats that
could be verified against real files on this Mac. Live capture covers every row regardless.

## Providers

Model name to provider, in `PROVIDERS`: Ollama tags (`name:tag`), OpenRouter prefixes, Anthropic (claude),
OpenAI (gpt, o-series, codex), Google (gemini, gemma), xAI (grok), DeepSeek, Moonshot (kimi), Alibaba (qwen,
qwq), Xiaomi (mimo), ByteDance (doubao, seed), Mistral (mistral, mixtral, codestral, devstral, magistral,
ministral, pixtral), Meta (llama), Nous (hermes), Z.ai (glm), MiniMax, Amazon (nova, titan), Cohere (command),
Microsoft (phi), NVIDIA (nemotron), IBM (granite), Perplexity (sonar), AI21 (jamba), Baidu (ernie), Tencent
(hunyuan), StepFun (step), 01.AI (yi), Reka, Writer (palmyra), Databricks (dbrx), Snowflake (arctic), AllenAI
(olmo), TII (falcon), Upstage (solar), LG (exaone), Inception (mercury).

When the model is unknown: the agent's default provider, else the single provider whose API key name is
present in the agent's environment (two or more keys is ambiguous and stays blank).

## Sources

- [awesome-cli-coding-agents](https://github.com/bradAGI/awesome-cli-coding-agents) (agent names, packages, vendors)
- [Gemini CLI shell tool](https://github.com/google-gemini/gemini-cli/blob/main/docs/tools/shell.md) (`GEMINI_CLI=1`)
- [Codex sandbox analysis](https://agent-safehouse.dev/docs/agent-investigations/codex) (`CODEX_SANDBOX`)
- [Codex CLI environment variables](https://codex.danielvaughan.com/2026/06/03/codex-cli-environment-variables-runtime-configuration-headless-ci-container-deployment/)
- [Cursor terminal tool](https://cursor.com/docs/agent/tools/terminal) (`CURSOR_AGENT`)
- [Grok Build overview](https://docs.x.ai/build/overview), [Grok Build configuration](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-pager/docs/user-guide/05-configuration.md) (`~/.grok`, `GROK_HOME`, `XAI_API_KEY`)
- [Grok Build developer guide](https://www.developersdigest.tech/blog/grok-build-developer-guide-2026)
- [Hermes Agent CLI](https://hermes-agent.nousresearch.com/docs/user-guide/cli/), [CLI reference](https://hermes-agent.nousresearch.com/docs/reference/cli-commands)
- [Antigravity CLI install](https://antigravity.google/docs/cli/install/), [hands-on guide](https://dev.to/arindam_1729/antigravity-cli-a-hands-on-guide-to-googles-terminal-coding-agent-5bc7) (`agy`, `~/.gemini/antigravity-cli/`)
- [Copilot CLI programmatic reference](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-programmatic-reference), [configuring Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/configure-copilot-cli)
- [Kimi Code CLI data locations](https://www.kimi-cli.com/en/configuration/data-locations.html)
- [ccusage OpenCode guide](https://ccusage.com/guide/opencode/) (OpenCode storage layout)
- [Amp CLI docs](https://github.com/lfglabs-dev/awesome-amp-code/blob/main/docs/amp_cli_docs.md), [Factory Droid sessions](https://deepwiki.com/factory-ai/factory/4.5-session-management), [Auggie](https://github.com/augmentcode/auggie)
- [Mistral Vibe](https://github.com/mistralai/mistral-vibe), [Qwen Code](https://pinggy.io/blog/best_open_source_cli_coding_agents/)
- [Warp third-party CLI agents](https://docs.warp.dev/agents/cli-agents/overview/)
- [Best CLI coding agents 2026](https://kilo.ai/articles/best-cli-coding-agents), [State of CLI coding agents](https://blog.arcbjorn.com/state-of-cli-coding-agents-2026), [Top 11 LLM API providers](https://futureagi.substack.com/p/top-11-llm-api-providers-in-2026), [LLM Gateway timeline](https://llmgateway.io/timeline)
