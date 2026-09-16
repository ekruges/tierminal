#!/usr/bin/env python3
"""Tierminal data engine.

Records every shell command you and any AI agent run, scores them, ranks you.

  hook        Claude Code PreToolUse/PostToolUse hook (hook JSON on stdin)
  ingest      fold new events.log records into the database
  backfill    import shell histories and every agent transcript found on this machine
  reclassify  recompute name/kind/host/provider for every stored command
  rescan      re-read every agent transcript from the start
  stats       ingest, then print the stats JSON the menu bar app renders
  setup shell | claude | status   wire the hooks (used by the app's first-run wizard and install.sh)
  remote add <ssh-host> | remote rm <ssh-host> | remote list
  sync        pull new events from every remote machine

Capture paths: the zsh/bash hooks log every interactive command and every
`-c` command string with the shell's ancestor process list; ingest matches
that ancestry against AGENTS, so any agent that spawns a shell is attributed
without a per-agent integration.
"""
import hashlib
import json
import os
import re
import socket
import sqlite3
import subprocess
import sys
import time
from datetime import date, datetime, timedelta

DATA = os.environ.get("TIERMINAL_DIR") or os.path.expanduser("~/Library/Application Support/Tierminal")
DB = os.path.join(DATA, "tierminal.db")
LOG = os.path.join(DATA, "events.log")
PENDING = os.path.join(DATA, "pending")
RS, FS, AS = "\x1e", "\x1f", "\x1d"
MACHINE = socket.gethostname().split(".")[0]
LOG_ROTATE_AT = 32 * 1024 * 1024

TIERS = ["Iron", "Bronze", "Silver", "Gold", "Platinum", "Diamond", "Ascendant", "Immortal", "Radiant", "Root"]
BASES = [0, 1000, 3000, 8000, 20000, 50000, 120000, 300000, 750000, 1000000]
ROMAN = ["", "I", "II", "III"]

AGENTS = [
    ("claude", "anthropic", r"claude/versions/|@anthropic-ai/claude-code|(^|/)claude( |$)|claw-code", False),
    ("codex", "openai", r"@openai/codex|(^|/)codex( |$)|Codex\.app", False),
    ("gemini", "google", r"@google/gemini-cli|(^|/)gemini( |$)", False),
    ("antigravity", "google", r"(^|/)agy( |$)|antigravity-cli", False),
    ("antigravity", "google", r"Antigravity\.app", True),
    ("jules", "google", r"(^|/)jules( |$)", False),
    ("grok", "xai", r"grok-build|grok-cli|(^|/)grok( |$)", False),
    ("hermes", "nous", r"hermes-agent|(^|/)hermes( |$)", False),
    ("opencode", "", r"opencode-ai|(^|/)opencode( |$)", False),
    ("pi", "", r"pi-mono|pi-coding-agent|(^|/)pi( |$)|oh-my-pi", False),
    ("openhands", "", r"openhands|all-hands", False),
    ("aider", "", r"(^|/)aider( |$)", False),
    ("goose", "", r"(^|/)goose( |$)", False),
    ("cline", "", r"(^|/)cline( |$)|claude-dev|saoudrizwan", False),
    ("roo", "", r"roo-cline|roo-code|(^|/)roo( |$)", False),
    ("kilo", "", r"kilo-code|kilocode|(^|/)kilo( |$)", False),
    ("continue", "", r"continuedev|continue-cli|(^|/)cn( |$)", False),
    ("crush", "", r"(^|/)crush( |$)", False),
    ("qwen", "alibaba", r"qwen-code|(^|/)qwen( |$)", False),
    ("kimi", "moonshot", r"kimi-cli|kimi-code|(^|/)kimi( |$)", False),
    ("mimo", "xiaomi", r"mimo-code|(^|/)mimo( |$)", False),
    ("trae", "bytedance", r"trae-agent", False),
    ("trae", "bytedance", r"Trae\.app", True),
    ("vibe", "mistral", r"mistral-vibe|(^|/)vibe( |$)", False),
    ("groq", "groq", r"groq-code-cli|(^|/)groq( |$)", False),
    ("neovate", "ant", r"neovate", False),
    ("deepseek", "deepseek", r"deepseek", False),
    ("ollama", "ollama", r"(^|/)ollama( |$)", False),
    ("amazonq", "amazon", r"\.local/bin/q( |$)|amazon-q|(^|/)qchat( |$)|codewhisperer", False),
    ("kiro", "amazon", r"kiro-cli", False),
    ("kiro", "amazon", r"Kiro\.app", True),
    ("copilot", "github", r"@github/copilot|copilot-cli|(^|/)copilot( |$)|github\.copilot", False),
    ("cursor", "", r"cursor-agent", False),
    ("cursor", "", r"Cursor\.app", True),
    ("windsurf", "", r"Windsurf\.app|codeium", True),
    ("warp", "", r"Warp\.app", True),
    ("zed", "", r"Zed\.app", True),
    ("auggie", "", r"@augmentcode/auggie|(^|/)auggie( |$)", False),
    ("droid", "", r"(^|/)droid( |$)|factory-cli|factory\.ai", False),
    ("amp", "", r"@sourcegraph/amp|(^|/)amp( |$)", False),
    ("junie", "jetbrains", r"(^|/)junie( |$)", False),
    ("cortex", "snowflake", r"cortex-code|(^|/)cortex( |$)", False),
    ("devin", "cognition", r"(^|/)devin( |$)", False),
    ("rovodev", "atlassian", r"rovodev|rovo-dev|(^|/)acli( |$)", False),
    ("tabnine", "", r"tabnine", False),
    ("codebuff", "", r"codebuff", False),
    ("plandex", "", r"plandex", False),
    ("letta", "", r"letta-code|(^|/)letta( |$)", False),
    ("deepagents", "", r"deepagents", False),
    ("swe-agent", "", r"swe-agent|sweagent", False),
    ("interpreter", "", r"open-interpreter|(^|/)interpreter( |$)", False),
    ("gptme", "", r"(^|/)gptme( |$)", False),
    ("ra-aid", "", r"ra-aid", False),
    ("kode", "", r"kode-cli|(^|/)kode( |$)", False),
    ("nanocoder", "", r"nanocoder", False),
    ("prime", "", r"prime-agent", False),
    ("openclaw", "", r"(^|/)openclaw( |$)|nanobot|zeroclaw|picoclaw|ironclaw|nullclaw", False),
]
AGENT_RX = [(n, re.compile(rx, re.I), ide) for n, _, rx, ide in AGENTS]
AGENT_PROVIDER = {n: p for n, p, _, _ in AGENTS}

MARKER_AGENTS = {"CLAUDECODE": "claude", "CLAUDE_CODE_ENTRYPOINT": "claude", "GEMINI_CLI": "gemini",
                 "CODEX_SANDBOX": "codex", "CODEX_SANDBOX_NETWORK_DISABLED": "codex", "CURSOR_AGENT": "cursor"}

MARKER_PROVIDERS = {
    "ANTHROPIC_API_KEY": "anthropic", "OPENAI_API_KEY": "openai", "GEMINI_API_KEY": "google",
    "GOOGLE_API_KEY": "google", "XAI_API_KEY": "xai", "GROK_API_KEY": "xai", "DEEPSEEK_API_KEY": "deepseek",
    "MOONSHOT_API_KEY": "moonshot", "KIMI_API_KEY": "moonshot", "DASHSCOPE_API_KEY": "alibaba",
    "QWEN_API_KEY": "alibaba", "MISTRAL_API_KEY": "mistral", "ZAI_API_KEY": "zai", "ZHIPU_API_KEY": "zai",
    "GLM_API_KEY": "zai", "MINIMAX_API_KEY": "minimax", "GROQ_API_KEY": "groq", "TOGETHER_API_KEY": "together",
    "FIREWORKS_API_KEY": "fireworks", "CEREBRAS_API_KEY": "cerebras", "OPENROUTER_API_KEY": "openrouter",
    "PERPLEXITY_API_KEY": "perplexity", "COHERE_API_KEY": "cohere", "HF_TOKEN": "huggingface",
    "HUGGINGFACE_API_KEY": "huggingface", "NVIDIA_API_KEY": "nvidia", "AZURE_OPENAI_API_KEY": "azure",
    "AWS_BEARER_TOKEN_BEDROCK": "bedrock", "OLLAMA_HOST": "ollama", "OLLAMA_MODEL": "ollama",
}

PROVIDERS = [
    ("ollama", r"^ollama[/:]|:[a-z0-9.\-]+$"),
    ("openrouter", r"^openrouter/"),
    ("anthropic", r"claude"), ("openai", r"^(gpt|o[1-9]|codex|chatgpt|text-|davinci)"),
    ("google", r"gemini|gemma|antigravity"), ("xai", r"grok"), ("deepseek", r"deepseek"),
    ("moonshot", r"kimi"), ("alibaba", r"qwen|qwq"), ("xiaomi", r"mimo"), ("bytedance", r"doubao|seed-"),
    ("mistral", r"mistral|mixtral|codestral|devstral|magistral|ministral|pixtral"), ("meta", r"llama"),
    ("nous", r"hermes"), ("zai", r"\bglm"), ("minimax", r"minimax"), ("amazon", r"\bnova|titan"),
    ("cohere", r"command-"), ("microsoft", r"\bphi-?[0-9]"), ("nvidia", r"nemotron"), ("ibm", r"granite"),
    ("perplexity", r"sonar|pplx"), ("ai21", r"jamba"), ("baidu", r"ernie"), ("tencent", r"hunyuan"),
    ("stepfun", r"^step-"), ("01ai", r"^yi-"), ("reka", r"reka"), ("writer", r"palmyra"),
    ("databricks", r"dbrx"), ("snowflake", r"arctic"), ("allenai", r"olmo"), ("tii", r"falcon"),
    ("upstage", r"solar"), ("lg", r"exaone"), ("inception", r"mercury"),
]
PROVIDER_RX = [(n, re.compile(rx, re.I)) for n, rx in PROVIDERS]

SSH = {"ssh", "mosh", "et", "sftp"}
MONITOR = {"htop", "top", "btop", "bpytop", "glances", "watch", "nvtop", "iostat", "vmstat",
           "iftop", "nethogs", "bmon", "nload", "mtr", "ping", "tcpdump"}
MONITOR_RE = re.compile(
    r"^(tail\s.*-[fF]\b|journalctl\s.*-f\b|less\s.*\+F\b|docker\s+stats\b|nvidia-smi\s.*(-l\b|dmon)"
    r"|(docker|podman|kubectl|pm2|fly|heroku|pct|qm)\s.*\blogs?\b.*(-f\b|--follow)|kubectl\s.*(-w\b|--watch))")
SUBCMD = {"git", "docker", "kubectl", "npm", "pnpm", "yarn", "brew", "cargo", "swift", "gh", "systemctl",
          "launchctl", "pip", "pip3", "uv", "go", "make", "tailscale", "pct", "qm", "claude", "codex", "ollama"}
WRAPPERS = {"nohup", "time", "command", "exec", "builtin", "env", "caffeinate", "nice", "timeout", "stdbuf", "unbuffer"}
NAMELESS = {"cd", "set", "export", "source", ".", "pushd", "popd", "true", "unset", "alias"}
SSH_ARG_OPTS = set("bBcDEeFIiJLlmOopQRSWw")
ASSIGN_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
SPLIT_RE = re.compile(r"\s*(?:&&|\|\||;|\||\n)\s*")
HIST_RE = re.compile(r"^: (\d+):(\d+);(.*)$")
CODEX_CMD_RE = re.compile(r'exec_command\(\{\s*cmd:\s*"((?:\\.|[^"\\])*)"')
SELF_RE = re.compile(r"tierminal\.py|shell-snapshots|tierminal\.(zsh|bash)")
SSH_DUR_CAP = 43200

COLS = "id, source, ts, dur, rc, cwd, cmd, name, kind, host, sudo, session, model, provider, machine"
INSERT = "INSERT OR %s INTO commands (" + COLS + ") VALUES (" + ",".join("?" * 15) + ")"
INSERT_REPLACE, INSERT_IGNORE = INSERT % "REPLACE", INSERT % "IGNORE"

def _h(s):
    return hashlib.sha1(s.encode("utf-8", "replace")).hexdigest()[:12]

def _strip(toks):
    sudo, i = False, 0
    while i < len(toks):
        t = toks[i]
        if t in ("sudo", "doas") or t in WRAPPERS:
            sudo = sudo or t in ("sudo", "doas")
            i += 1
            while i < len(toks) and toks[i].startswith("-"):
                i += 1
            if t == "timeout":
                i += 1
            continue
        if ASSIGN_RE.match(t):
            i += 1
            continue
        break
    return toks[i:], sudo

def _ssh_host(toks):
    i = 1
    while i < len(toks):
        t = toks[i]
        if t.startswith("-"):
            i += 2 if (len(t) == 2 and t[1] in SSH_ARG_OPTS) else 1
            continue
        return t.split("@")[-1].split(":")[0].strip("'\"") or None
    return None

def classify(cmd):
    name, kind, host, sudo, weak = "", "other", None, False, True
    for seg in SPLIT_RE.split(cmd.strip()):
        toks, s = _strip(seg.split())
        sudo = sudo or s
        if not toks:
            continue
        base = os.path.basename(toks[0]).strip("'\"()`{}$")
        if not base:
            continue
        if weak:
            weak, name = base in NAMELESS, base
            if base in SUBCMD and len(toks) > 1 and not toks[1].startswith("-"):
                name = base + " " + toks[1]
        if base in SSH and kind != "ssh":
            kind, host = "ssh", _ssh_host(toks)
        elif kind == "other" and (base in MONITOR or MONITOR_RE.match(" ".join(toks))):
            kind = "monitor"
    return name, kind, host, sudo

def agent_of(anc, markers, interactive):
    for line in anc.split(AS):
        for name, rx, ide in AGENT_RX:
            if (not ide or not interactive) and rx.search(line):
                return name
    for m in markers.split():
        if m in MARKER_AGENTS:
            return MARKER_AGENTS[m]
    return ""

def provider_of(model, agent, markers=""):
    for name, rx in PROVIDER_RX:
        if model and rx.search(model):
            return name
    if AGENT_PROVIDER.get(agent):
        return AGENT_PROVIDER[agent]
    hints = {MARKER_PROVIDERS[m] for m in markers.split() if m in MARKER_PROVIDERS}
    return hints.pop() if len(hints) == 1 else ""

def rank(xp):
    t = max(i for i, b in enumerate(BASES) if xp >= b)
    if t == len(BASES) - 1:
        return {"tier": t, "division": 0, "rank": TIERS[t], "divStart": BASES[t], "divEnd": None}
    span = (BASES[t + 1] - BASES[t]) / 3.0
    d = min(3, int((xp - BASES[t]) // span) + 1)
    return {"tier": t, "division": d, "rank": "%s %s" % (TIERS[t], ROMAN[d]),
            "divStart": int(BASES[t] + span * (d - 1)), "divEnd": int(BASES[t] + span * d)}

def row(id_, source, ts, dur, rc, cwd, cmd, session="", model="", machine=MACHINE, markers=""):
    name, kind, host, sudo = classify(cmd)
    provider = "" if source == "user" else provider_of(model, source, markers)
    return (id_, source, ts, dur, rc, cwd, cmd, name, kind, host, int(sudo), session, model or "", provider, machine)

def open_db():
    os.makedirs(DATA, exist_ok=True)
    db = sqlite3.connect(DB, timeout=10)
    db.executescript("""
        CREATE TABLE IF NOT EXISTS commands (
            id TEXT PRIMARY KEY, source TEXT, ts REAL, dur REAL, rc INTEGER, cwd TEXT, cmd TEXT,
            name TEXT, kind TEXT, host TEXT, sudo INTEGER, session TEXT, model TEXT, provider TEXT, machine TEXT);
        CREATE INDEX IF NOT EXISTS commands_ts ON commands(ts);
        CREATE INDEX IF NOT EXISTS commands_kind ON commands(kind);
        CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT);
    """)
    have = {r[1] for r in db.execute("PRAGMA table_info(commands)")}
    for col in ("model", "provider", "machine"):
        if col not in have:
            db.execute("ALTER TABLE commands ADD COLUMN %s TEXT" % col)
    db.execute("UPDATE commands SET machine=? WHERE machine IS NULL", (MACHINE,))
    db.execute("UPDATE commands SET provider='anthropic' WHERE source='claude' AND provider IS NULL")
    db.commit()
    return db

def meta_get(db, key, default):
    r = db.execute("SELECT value FROM meta WHERE key=?", (key,)).fetchone()
    return r[0] if r else default

def meta_set(db, key, value):
    db.execute("INSERT OR REPLACE INTO meta VALUES (?,?)", (key, value))

def append(fields):
    os.makedirs(DATA, exist_ok=True)
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(FS.join(fields) + RS + "\n")

def hook():
    try:
        d = json.load(sys.stdin)
    except ValueError:
        return
    if d.get("tool_name") != "Bash":
        return
    inp = d.get("tool_input") or {}
    cmd = inp.get("command", "") if isinstance(inp, dict) else ""
    if not isinstance(cmd, str) or not cmd.strip():
        return
    tid = d.get("tool_use_id") or ""
    os.makedirs(PENDING, exist_ok=True)
    p = os.path.join(PENDING, tid or _h(d.get("session_id", "") + cmd))
    now = time.time()
    if d.get("hook_event_name") == "PreToolUse":
        with open(p, "w") as f:
            f.write(repr(now))
        return
    try:
        with open(p) as f:
            t0 = float(f.read())
        os.remove(p)
    except (OSError, ValueError):
        t0 = now
    append(("claude", repr(t0), repr(now), str(_rc(d.get("tool_response"))), d.get("cwd", ""), cmd, tid,
            _claude_model(d.get("transcript_path", "")), MACHINE, "", ""))

def _rc(resp):
    if isinstance(resp, dict):
        for k in ("exit_code", "exitCode", "returnCode"):
            if isinstance(resp.get(k), int):
                return resp[k]
        return 1 if (resp.get("is_error") or resp.get("interrupted")) else 0
    if isinstance(resp, str) and resp.lstrip().startswith(("Error", "Exit code")):
        return 1
    return 0

def _claude_model(path):
    try:
        with open(path, "rb") as f:
            f.seek(0, 2)
            f.seek(max(0, f.tell() - 262144))
            names = re.findall(rb'"model":"([^"<]+)"', f.read())
        return names[-1].decode("utf-8", "replace") if names else ""
    except OSError:
        return ""

def parse_record(rec):
    parts = rec.lstrip("\n").split(FS)
    if len(parts) < 6:
        return None
    parts += [""] * (11 - len(parts))
    mode, t0, t1, rc, cwd, cmd, tid, model, machine, anc, markers = parts[:11]
    cmd = cmd.rstrip()
    try:
        t0, t1 = float(t0), float(t1)
        rc = int(rc) if rc not in ("", "None") else None
    except ValueError:
        return None
    if not cmd or SELF_RE.search(cmd):
        return None
    if mode in ("claude", "user"):
        agent = mode
    else:
        agent = agent_of(anc, markers, mode == "i") or ("user" if mode == "i" else "")
        if not agent:
            return None
    id_ = "claude:" + tid if tid else "%s:%d:%s" % (agent, int(t0), _h(cmd))
    return row(id_, agent, t0, max(0.0, t1 - t0), rc, cwd, cmd, "", model, machine or MACHINE, markers)

def ingest(db):
    off = int(meta_get(db, "log_offset", "0"))
    try:
        size = os.path.getsize(LOG)
    except OSError:
        return 0
    if size < off:
        off = 0
    if size == off:
        return 0
    with open(LOG, "rb") as f:
        f.seek(off)
        raw = f.read()
    end = raw.rfind(RS.encode())
    if end < 0:
        return 0
    rows = [r for r in (parse_record(rec) for rec in raw[:end].decode("utf-8", "replace").split(RS)) if r]
    db.executemany(INSERT_REPLACE, rows)
    off += end + 1
    meta_set(db, "log_offset", str(off))
    db.commit()
    if off > LOG_ROTATE_AT:

        with open(LOG, "rb") as f:
            f.seek(off)
            rest = f.read()
        with open(LOG + ".tmp", "wb") as f:
            f.write(rest)
        os.replace(LOG + ".tmp", LOG)
        meta_set(db, "log_offset", "0")
        db.commit()
    _sweep_pending()
    return len(rows)

def _sweep_pending():
    cutoff = time.time() - 86400
    try:
        for fn in os.listdir(PENDING):
            p = os.path.join(PENDING, fn)
            if os.path.getmtime(p) < cutoff:
                os.remove(p)
    except OSError:
        pass

def parse_history(text):
    rows, cur = [], None

    def flush():
        if cur and cur[2].strip():
            ts, dur, cmd = cur[0], cur[1], cur[2].rstrip()
            rows.append(row("user:%d:%s" % (ts, _h(cmd)), "user", float(ts), float(dur) if dur > 0 else None,
                            None, "", cmd))

    for line in text.split("\n"):
        m = HIST_RE.match(line)
        if m:
            flush()
            cur = (int(m.group(1)), int(m.group(2)), m.group(3))
        elif cur is not None and cur[2].endswith("\\"):
            cur = (cur[0], cur[1], cur[2][:-1] + "\n" + line)
    flush()
    return rows

def backfill_history(db):
    n = 0
    for name in (".zsh_history", ".bash_history"):
        path = os.path.expanduser("~/" + name)
        try:
            with open(path, "rb") as f:
                text = f.read().decode("utf-8", "replace")
        except OSError:
            continue
        rows = parse_history(text)
        db.executemany(INSERT_IGNORE, rows)
        n += len(rows)
    db.commit()
    return n

def backfill_amazonq(db):
    path = os.path.expanduser("~/Library/Application Support/amazon-q/data.sqlite3")
    if not os.path.exists(path):
        return 0
    try:
        src = sqlite3.connect("file:%s?mode=ro" % path, uri=True)
        rows = src.execute("SELECT command, cwd, start_time, duration, exit_code, hostname FROM history").fetchall()
        src.close()
    except sqlite3.Error:
        return 0
    out = []
    for cmd, cwd, t0, dur, rc, host in rows:
        if not cmd or not t0 or SELF_RE.search(cmd):
            continue
        cmd = cmd.rstrip()
        out.append(row("user:%d:%s" % (t0, _h(cmd)), "user", float(t0), dur / 1000.0 if dur else None,
                       rc, cwd or "", cmd))
    db.executemany(INSERT_REPLACE, out)
    db.commit()
    return len(out)

def _iso(s):
    if not s:
        return None
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None

def _walk_jsonl(db, root, key_prefix, parse):
    n = 0
    for dirpath, _, files in os.walk(os.path.expanduser(root)):
        for fn in files:
            if not fn.endswith(".jsonl"):
                continue
            path = os.path.join(dirpath, fn)
            key = key_prefix + path
            off = int(meta_get(db, key, "0"))
            try:
                size = os.path.getsize(path)
            except OSError:
                continue
            if size <= off:
                continue
            with open(path, "rb") as f:
                f.seek(off)
                raw = f.read()
            end = raw.rfind(b"\n")
            if end < 0:
                continue
            rows = parse(raw[:end])
            db.executemany(INSERT_IGNORE, rows)
            db.executemany("UPDATE commands SET model=?, provider=? WHERE id=? AND (model IS NULL OR model='')",
                           [(r[12], r[13], r[0]) for r in rows if r[12]])
            meta_set(db, key, str(off + end + 1))
            n += len(rows)
    db.commit()
    return n

def transcript_rows(raw):
    rows, pending = [], {}
    for line in raw.split(b"\n"):
        if b'"tool_use"' not in line and b'"tool_result"' not in line:
            continue
        try:
            d = json.loads(line)
        except ValueError:
            continue
        msg = d.get("message") or {}
        content = msg.get("content") if isinstance(msg, dict) else None
        if not isinstance(content, list):
            continue
        ts = _iso(d.get("timestamp"))
        if ts is None:
            continue
        if d.get("type") == "assistant":
            model = msg.get("model") or ""
            for c in content:
                if isinstance(c, dict) and c.get("type") == "tool_use" and c.get("name") == "Bash":
                    cmd = (c.get("input") or {}).get("command") or ""
                    if isinstance(cmd, str) and cmd.strip() and c.get("id"):
                        pending[c["id"]] = (ts, d.get("cwd", ""), cmd.rstrip(), d.get("sessionId", ""), model)
        elif d.get("type") == "user":
            for c in content:
                if isinstance(c, dict) and c.get("type") == "tool_result" and c.get("tool_use_id") in pending:
                    t0, cwd, cmd, sess, model = pending.pop(c["tool_use_id"])
                    rows.append(row("claude:" + c["tool_use_id"], "claude", t0, max(0.0, ts - t0),
                                    1 if c.get("is_error") else 0, cwd, cmd, sess, model))
    for tid, (t0, cwd, cmd, sess, model) in pending.items():
        rows.append(row("claude:" + tid, "claude", t0, None, None, cwd, cmd, sess, model))
    return rows

def _codex_cmd(p):
    name = p.get("name") or ""
    if p.get("type") == "custom_tool_call" and name == "exec":
        m = CODEX_CMD_RE.search(p.get("input") or "")
        if m:
            try:
                return json.loads('"' + m.group(1) + '"')
            except ValueError:
                return m.group(1)
        return None
    if p.get("type") == "local_shell_call":
        c = (p.get("action") or {}).get("command")
        return " ".join(c) if isinstance(c, list) else c
    if p.get("type") == "function_call" and name in ("shell", "exec_command", "container.exec", "shell_command"):
        try:
            a = json.loads(p.get("arguments") or "{}")
        except ValueError:
            return None
        c = a.get("command") or a.get("cmd")
        if isinstance(c, list):
            c = c[-1] if len(c) >= 3 and c[1] in ("-lc", "-c") else " ".join(c)
        return c if isinstance(c, str) else None
    return None

def codex_rows(raw):
    rows, pending, cwd, model, sess = [], {}, "", "", ""
    for line in raw.split(b"\n"):
        try:
            d = json.loads(line)
        except ValueError:
            continue
        p = d.get("payload") or {}
        t = d.get("type")
        if t == "session_meta":
            cwd, sess, model = p.get("cwd", ""), p.get("id", ""), p.get("model") or model
        elif t == "turn_context":
            cwd, model = p.get("cwd") or cwd, p.get("model") or model
        elif t == "response_item":
            ts = _iso(d.get("timestamp"))
            cmd = _codex_cmd(p)
            if cmd is not None and ts is not None and cmd.strip():
                pending[p.get("call_id") or p.get("id")] = (ts, cwd, cmd.rstrip())
            elif p.get("type") in ("custom_tool_call_output", "function_call_output", "local_shell_call_output"):
                cid = p.get("call_id")
                if cid in pending and ts is not None:
                    t0, c, cmd = pending.pop(cid)
                    rows.append(row("codex:" + cid, "codex", t0, max(0.0, ts - t0), None, c, cmd, sess, model))
    for cid, (t0, c, cmd) in pending.items():
        rows.append(row("codex:" + cid, "codex", t0, None, None, c, cmd, sess, model))
    return rows

def backfill_agents(db):
    return {
        "claude": _walk_jsonl(db, "~/.claude/projects", "tx:", transcript_rows),
        "codex": _walk_jsonl(db, "~/.codex/sessions", "codex:", codex_rows),
        "amazonq": backfill_amazonq(db),
    }

def _hosts(db):
    return json.loads(meta_get(db, "hosts", "[]"))

REMOTE_DIR = "~/.local/share/tierminal"
REMOTE_LINE = 'export TIERMINAL_DIR="$HOME/.local/share/tierminal" TIERMINAL_REMOTE=1; [ -f "$TIERMINAL_DIR/tierminal.%s" ] && . "$TIERMINAL_DIR/tierminal.%s"'

def remote(db, argv):
    op = argv[0] if argv else "list"
    hosts = _hosts(db)
    if op == "list":
        print("\n".join(hosts) or "(none)")
        return
    host = argv[1]
    if op == "rm":
        meta_set(db, "hosts", json.dumps([h for h in hosts if h != host]))
        db.commit()
        return
    here = os.path.dirname(os.path.abspath(__file__))
    subprocess.run(["ssh", "-o", "ConnectTimeout=8", host, "mkdir -p " + REMOTE_DIR], check=True)
    subprocess.run(["scp", "-q", os.path.join(here, "tierminal.zsh"), os.path.join(here, "tierminal.bash"),
                    host + ":" + REMOTE_DIR + "/"], check=True)
    script = "\n".join([
        'for f in ~/.bashrc ~/.profile; do grep -q tierminal "$f" 2>/dev/null || printf "\\n# Tierminal\\n%s\\n" \'%s\' >> "$f"; done' % ("%s", REMOTE_LINE % ("bash", "bash")),
        'grep -q tierminal ~/.zshenv 2>/dev/null || printf "\\n# Tierminal\\n%s\\n" \'%s\' >> ~/.zshenv' % ("%s", REMOTE_LINE % ("zsh", "zsh")),
    ])
    subprocess.run(["ssh", host, script], check=True)
    if host not in hosts:
        meta_set(db, "hosts", json.dumps(hosts + [host]))
        db.commit()
    print("installed on " + host)

def sync(db):
    pulled = 0
    for host in _hosts(db):
        key = "remote:" + host
        off = int(meta_get(db, key, "0"))
        try:
            r = subprocess.run(["ssh", "-o", "ConnectTimeout=4", "-o", "BatchMode=yes", host,
                                "tail -c +%d %s/events.log 2>/dev/null" % (off + 1, REMOTE_DIR)],
                               capture_output=True, timeout=20)
        except (subprocess.TimeoutExpired, OSError):
            continue
        if r.returncode != 0 or not r.stdout:
            continue
        end = r.stdout.rfind(RS.encode())
        if end < 0:
            continue
        with open(LOG, "ab") as f:
            f.write(r.stdout[:end + 1])
        meta_set(db, key, str(off + end + 1))
        db.commit()
        pulled += end + 1
    return ingest(db) if pulled else 0

HERE = os.path.dirname(os.path.abspath(__file__))

def _add_line(path, needle, line):
    path = os.path.expanduser(path)
    try:
        with open(path) as f:
            if needle in f.read():
                return False
    except OSError:
        pass
    with open(path, "a") as f:
        f.write("\n# Tierminal command tracker\n%s\n" % line)
    return True

def _has(path, needle):
    try:
        with open(os.path.expanduser(path)) as f:
            return needle in f.read()
    except OSError:
        return False

def setup(db, argv):
    what = argv[0] if argv else "status"
    zsh, bash = os.path.join(HERE, "tierminal.zsh"), os.path.join(HERE, "tierminal.bash")
    if what == "shell":
        _add_line("~/.zshenv", "tierminal.zsh", '[ -f "%s" ] && source "%s"' % (zsh, zsh))
        for rc in ("~/.bashrc", "~/.profile"):
            _add_line(rc, "tierminal.bash", '[ -f "%s" ] && . "%s"' % (bash, bash))
        if os.path.exists(os.path.expanduser("~/.bash_profile")):
            _add_line("~/.bash_profile", "tierminal.bash", '[ -f "%s" ] && . "%s"' % (bash, bash))
        subprocess.run(["launchctl", "setenv", "BASH_ENV", bash])
        print("ok")
    elif what == "claude":
        if not os.path.isdir(os.path.expanduser("~/.claude")):
            print("absent")
            return
        path = os.path.expanduser("~/.claude/settings.json")
        try:
            with open(path) as f:
                s = json.load(f)
        except (OSError, ValueError):
            s = {}
        hooks = s.setdefault("hooks", {})
        cmd = '/usr/bin/python3 "%s" hook' % os.path.join(HERE, "tierminal.py")
        for ev in ("PreToolUse", "PostToolUse"):
            lst = hooks.setdefault(ev, [])
            if any("tierminal.py" in h.get("command", "") for e in lst for h in e.get("hooks", [])):
                continue
            lst.append({"matcher": "Bash", "hooks": [{"type": "command", "command": cmd, "timeout": 5}]})
        with open(path, "w") as f:
            json.dump(s, f, indent=2)
            f.write("\n")
        print("ok")
    else:
        json.dump({
            "shell": _has("~/.zshenv", "tierminal.zsh"),
            "claude": _has("~/.claude/settings.json", "tierminal.py"),
            "claudeInstalled": os.path.isdir(os.path.expanduser("~/.claude")),
            "commands": db.execute("SELECT COUNT(*) FROM commands").fetchone()[0],
        }, sys.stdout)

def reclassify(db):
    rows = db.execute("SELECT id, cmd, source, model FROM commands").fetchall()
    upd = []
    for id_, cmd, src, model in rows:
        n, k, h, s = classify(cmd)
        upd.append((n, k, h, int(s), "" if src == "user" else provider_of(model or "", src), id_))
    db.executemany("UPDATE commands SET name=?, kind=?, host=?, sudo=?, provider=? WHERE id=?", upd)
    db.commit()
    return len(upd)

AUTO_EVERY = 90


def auto_backfill(db):
    now = time.time()
    if now - float(meta_get(db, "last_auto", "0")) < AUTO_EVERY:
        return
    meta_set(db, "last_auto", repr(now))
    db.commit()
    try:
        backfill_history(db)
        backfill_agents(db)
    except (OSError, sqlite3.Error):
        pass


def stats(db):
    ingest(db)
    auto_backfill(db)
    q = lambda sql, *a: db.execute(sql, a).fetchall()
    one = lambda sql, *a: db.execute(sql, a).fetchone()[0]

    total = one("SELECT COUNT(*) FROM commands")
    user = one("SELECT COUNT(*) FROM commands WHERE source='user'")
    ssh_s = one("SELECT COALESCE(SUM(MIN(dur,?)),0) FROM commands WHERE kind='ssh' AND dur IS NOT NULL", SSH_DUR_CAP)
    mon_s = one("SELECT COALESCE(SUM(MIN(dur,?)),0) FROM commands WHERE kind='monitor' AND dur IS NOT NULL", SSH_DUR_CAP)
    xp_ssh, xp_mon = int(ssh_s // 60), int(mon_s // 60)
    xp = total + xp_ssh + xp_mon
    r = rank(xp)

    per_day = {}
    for d, c in q("SELECT date(ts,'unixepoch','localtime') d, COUNT(*) FROM commands GROUP BY d"):
        per_day.setdefault(d, [0, 0.0, 0.0])[0] = c
    for d, k, s in q("SELECT date(ts,'unixepoch','localtime') d, kind, SUM(MIN(dur,?)) FROM commands"
                     " WHERE kind IN ('ssh','monitor') AND dur IS NOT NULL GROUP BY d, kind", SSH_DUR_CAP):
        per_day.setdefault(d, [0, 0.0, 0.0])[1 if k == "ssh" else 2] = s
    days = {d: v[0] for d, v in per_day.items()}
    cum, c, s, m = [], 0, 0.0, 0.0
    for d in sorted(per_day):
        c, s, m = c + per_day[d][0], s + per_day[d][1], m + per_day[d][2]
        cum.append((d, c + int(s // 60) + int(m // 60)))

    def xp_at(day):
        iso, v = day.isoformat(), 0
        for d, x in cum:
            if d > iso:
                break
            v = x
        return v

    today = date.today()
    cnt = lambda d: days.get(d.isoformat(), 0)
    streak, d = 0, today if cnt(today) else today - timedelta(days=1)
    while cnt(d):
        streak, d = streak + 1, d - timedelta(days=1)
    longest = run = 0
    prev = None
    for ds in sorted(days):
        dd = date.fromisoformat(ds)
        run = run + 1 if prev and (dd - prev).days == 1 else 1
        longest, prev = max(longest, run), dd

    start = today - timedelta(days=52 * 7 + (today.weekday() + 1) % 7)
    heat, months, last, d, i = [], [], None, start, 0
    while d <= today:
        heat.append(cnt(d))
        if i % 7 == 0 and d.strftime("%b") != last:
            last = d.strftime("%b")
            months.append({"col": i // 7, "label": last})
        d, i = d + timedelta(days=1), i + 1

    hours = [[0] * 24 for _ in range(7)]
    for w, h, c in q("SELECT CAST(strftime('%w',ts,'unixepoch','localtime') AS INT),"
                     " CAST(strftime('%H',ts,'unixepoch','localtime') AS INT), COUNT(*) FROM commands GROUP BY 1,2"):
        hours[w][h] = c
    by_hour = [sum(hours[w][h] for w in range(7)) for h in range(24)]

    xp_week = xp - xp_at(today - timedelta(days=7))
    rate = xp_week / 7.0
    eta = int(-(-(r["divEnd"] - xp) // rate)) if r["divEnd"] and rate > 0 else None
    rank_since = next((d for d, x in cum if x >= r["divStart"]), "")
    ai = total - user
    squash = lambda t: re.sub(r"\s+", " ", t).strip()[:160]

    out = {
        "machine": MACHINE,
        "total": total, "user": user, "claude": ai, "ai": ai,
        "today": cnt(today),
        "week": sum(cnt(today - timedelta(days=k)) for k in range(7)),
        "month": sum(cnt(today - timedelta(days=k)) for k in range(30)),
        "xp": xp, "xpCommands": total, "xpSsh": xp_ssh, "xpMonitor": xp_mon,
        "xpWeek": xp_week, "xpToday": xp - xp_at(today - timedelta(days=1)),
        "xpHistory": [xp_at(today - timedelta(days=k)) for k in range(29, -1, -1)],
        "etaDays": eta, "rankSince": rank_since,
        "streak": streak, "longestStreak": longest, "activeDays": len(days),
        "sshSeconds": ssh_s, "monitorSeconds": mon_s,
        "failRate": one("SELECT COALESCE(AVG(rc != 0),0) FROM commands WHERE rc IS NOT NULL"),
        "sudoCount": one("SELECT COUNT(*) FROM commands WHERE sudo=1"),
        "hostsDistinct": one("SELECT COUNT(DISTINCT host) FROM commands WHERE kind='ssh' AND host IS NOT NULL"),
        "charsTyped": one("SELECT COALESCE(SUM(LENGTH(cmd)),0) FROM commands WHERE source='user'"),
        "distinctCommands": one("SELECT COUNT(DISTINCT cmd) FROM commands"),
        "sessions": one("SELECT COUNT(DISTINCT session) FROM commands WHERE session != '' AND session IS NOT NULL"),
        "heat": heat, "heatMonths": months, "hours": hours,
        "busiestHour": max(range(24), key=lambda h: by_hour[h]) if total else 0,
        "busiestDay": ({"date": max(days, key=days.get), "count": max(days.values())} if days else None),
        "agents": [{"name": n, "count": c, "seconds": s} for n, c, s in
                   q("SELECT source, COUNT(*), COALESCE(SUM(MIN(dur,?)),0) FROM commands GROUP BY source ORDER BY 2 DESC", SSH_DUR_CAP)],
        "providers": [{"name": n, "count": c} for n, c in
                      q("SELECT COALESCE(NULLIF(provider,''),'unknown'), COUNT(*) FROM commands WHERE source != 'user'"
                        " GROUP BY 1 ORDER BY 2 DESC")],
        "models": [{"name": n, "count": c} for n, c in
                   q("SELECT model, COUNT(*) FROM commands WHERE model != '' AND model IS NOT NULL GROUP BY model ORDER BY 2 DESC LIMIT 8")],
        "machines": [{"name": n, "count": c} for n, c in
                     q("SELECT COALESCE(machine,''), COUNT(*) FROM commands GROUP BY 1 ORDER BY 2 DESC")],
        "topCommands": [{"name": n, "count": c} for n, c in
                        q("SELECT name, COUNT(*) c FROM commands WHERE name != '' GROUP BY name ORDER BY c DESC LIMIT 10")],
        "longest": [{"cmd": squash(c), "dur": du, "ts": ts, "source": s} for c, du, ts, s in
                    q("SELECT cmd, dur, ts, source FROM commands WHERE dur IS NOT NULL AND dur < 604800"
                      " AND kind='other' AND COALESCE(rc,0)=0 ORDER BY dur DESC LIMIT 8")],
        "sshHosts": [{"host": h, "seconds": s, "count": c} for h, s, c in
                     q("SELECT host, COALESCE(SUM(MIN(dur,?)),0), COUNT(*) FROM commands WHERE kind='ssh'"
                       " AND host IS NOT NULL GROUP BY host ORDER BY 2 DESC, 3 DESC LIMIT 8", SSH_DUR_CAP)],
        "recent": [{"cmd": squash(c), "source": s, "ts": ts} for c, s, ts in
                   q("SELECT cmd, source, ts FROM commands ORDER BY ts DESC LIMIT 6")],
        "since": (datetime.fromtimestamp(one("SELECT MIN(ts) FROM commands")).strftime("%Y-%m-%d") if total else ""),
        "ladder": BASES, "tiers": TIERS, "remotes": _hosts(db),
    }
    out.update(r)
    out["shareText"] = "%s · %s XP · %s commands · %dd streak · %dh in ssh · %d%% run by AI #tierminal" % (
        r["rank"], format(xp, ","), format(total, ","), streak, int(ssh_s // 3600), round(100.0 * ai / total) if total else 0)
    return out

def main(argv):
    cmd = argv[1] if len(argv) > 1 else "stats"
    if cmd == "hook":
        hook()
        return
    db = open_db()
    if cmd == "ingest":
        print(ingest(db))
    elif cmd == "backfill":
        print("history: %d rows, agents: %s" % (backfill_history(db), backfill_agents(db)))
    elif cmd == "rescan":
        db.execute("DELETE FROM meta WHERE key LIKE 'tx:%' OR key LIKE 'codex:%'")
        db.commit()
        print("agents: %s" % backfill_agents(db))
    elif cmd == "reclassify":
        print(reclassify(db))
    elif cmd == "setup":
        setup(db, argv[2:])
    elif cmd == "remote":
        remote(db, argv[2:])
    elif cmd == "sync":
        print(sync(db))
    elif cmd == "stats":
        json.dump(stats(db), sys.stdout)
    else:
        sys.exit(__doc__)

if __name__ == "__main__":
    main(sys.argv)
