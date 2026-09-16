[ -n "$TIERMINAL_OFF" ] && return 0 2>/dev/null
[ -n "$CLAUDECODE" ] && [ -z "$TIERMINAL_REMOTE" ] && return 0 2>/dev/null
[ -n "$_tmd_loaded" ] && return 0 2>/dev/null
_tmd_loaded=1
_tmd_dir="${TIERMINAL_DIR:-$HOME/Library/Application Support/Tierminal}"
_tmd_log="$_tmd_dir/events.log"
_tmd_host="$(hostname -s 2>/dev/null || hostname)"
_tmd_cmd="" _tmd_t0="" _tmd_anc="" _tmd_markers="" _tmd_model=""
[ -d "$_tmd_dir" ] || mkdir -p "$_tmd_dir" 2>/dev/null
[ -z "$BASH_ENV" ] && export BASH_ENV="${BASH_SOURCE[0]}"

_tmd_now() { if [ -n "$EPOCHREALTIME" ]; then printf '%s' "$EPOCHREALTIME"; else date +%s; fi; }

_tmd_scan() {
  local v
  _tmd_anc="$(ps -axo pid=,ppid=,command= 2>/dev/null | awk -v p="$PPID" '{pp[$1]=$2; c=$0; sub(/^ *[0-9]+ +[0-9]+ +/, "", c); cmd[$1]=substr(c,1,160)} END{for(i=0;i<8&&p>1;i++){printf "%s\035", cmd[p]; p=pp[p]}}')"
  for v in $(compgen -e 2>/dev/null || env | cut -d= -f1); do
    case $v in
      *_API_KEY|*_MODEL|CLAUDECODE|CLAUDE_CODE_*|GEMINI_CLI|CODEX_SANDBOX*|CURSOR_AGENT|OLLAMA_*|HF_TOKEN|AGY_*)
        [ -n "${!v}" ] && _tmd_markers="$_tmd_markers$v ";;
    esac
  done
  for v in ANTHROPIC_MODEL CLAUDE_MODEL OPENAI_MODEL CODEX_MODEL GEMINI_MODEL COPILOT_MODEL AIDER_MODEL GOOSE_MODEL HERMES_MODEL OLLAMA_MODEL GROK_MODEL KIMI_MODEL QWEN_MODEL OPENCODE_MODEL CRUSH_MODEL VIBE_MODEL AMP_MODEL CLINE_MODEL DROID_MODEL LLM_MODEL MODEL_NAME MODEL; do
    [ -n "${!v}" ] && { _tmd_model="${!v}"; break; }
  done
}

_tmd_write() {
  printf '%s\037%s\037%s\037%s\037%s\037%s\037\037%s\037%s\037%s\037%s\036\n' \
    "$1" "$2" "$(_tmd_now)" "$3" "$PWD" "$4" "$_tmd_model" "$_tmd_host" "$_tmd_anc" "$_tmd_markers" >> "$_tmd_log" 2>/dev/null
}

if [[ $- == *i* ]]; then
  _tmd_scan
  unset TIERMINAL_ANC TIERMINAL_MARKERS TIERMINAL_MODEL
  _tmd_pre() { [ -n "$COMP_LINE" ] && return 0; [ -n "$_tmd_cmd" ] && return 0; _tmd_cmd="$BASH_COMMAND"; _tmd_t0="$(_tmd_now)"; }
  _tmd_post() {
    local rc=$? line
    [ -n "$_tmd_cmd" ] || return 0
    line="$(HISTTIMEFORMAT= builtin history 1 2>/dev/null)"
    line="${line#"${line%%[![:space:]]*}"}"; line="${line#*[[:space:]]}"
    _tmd_write i "$_tmd_t0" "$rc" "${line:-$_tmd_cmd}"
    _tmd_cmd=""
  }
  trap '_tmd_pre' DEBUG
  PROMPT_COMMAND="_tmd_post${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
elif [ -n "$BASH_EXECUTION_STRING" ]; then
  if [ -n "$TIERMINAL_ANC" ]; then
    _tmd_anc="$(ps -o command= -p $PPID 2>/dev/null | cut -c1-160)"$'\035'"$TIERMINAL_ANC"
    _tmd_markers="$TIERMINAL_MARKERS" _tmd_model="$TIERMINAL_MODEL"
  else
    _tmd_scan
    export TIERMINAL_ANC="$_tmd_anc" TIERMINAL_MARKERS="$_tmd_markers" TIERMINAL_MODEL="$_tmd_model"
  fi
  _tmd_t0="$(_tmd_now)"
  trap '_tmd_write c "$_tmd_t0" "$?" "$BASH_EXECUTION_STRING"' EXIT
fi
