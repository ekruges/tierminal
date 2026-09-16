[[ -n "$TIERMINAL_OFF" ]] && return 0
[[ -n "$CLAUDECODE" && -z "$TIERMINAL_REMOTE" ]] && return 0
zmodload zsh/datetime 2>/dev/null || return 0
typeset -g _tmd_dir="${TIERMINAL_DIR:-$HOME/Library/Application Support/Tierminal}"
typeset -g _tmd_log="$_tmd_dir/events.log"
typeset -g _tmd_host="${HOST%%.*}"
typeset -g _tmd_cmd="" _tmd_t0="" _tmd_anc="" _tmd_markers="" _tmd_model=""
[[ -d "$_tmd_dir" ]] || mkdir -p "$_tmd_dir" 2>/dev/null
[[ -z "$BASH_ENV" && -f "${${(%):-%x}:h}/tierminal.bash" ]] && export BASH_ENV="${${(%):-%x}:h}/tierminal.bash"

_tmd_scan() {
  local v
  _tmd_anc="$(ps -axo pid=,ppid=,command= 2>/dev/null | awk -v p="$PPID" '{pp[$1]=$2; c=$0; sub(/^ *[0-9]+ +[0-9]+ +/, "", c); cmd[$1]=substr(c,1,160)} END{for(i=0;i<8&&p>1;i++){printf "%s\035", cmd[p]; p=pp[p]}}')"
  for v in ${(k)parameters}; do
    case $v in
      (*_API_KEY|*_MODEL|CLAUDECODE|CLAUDE_CODE_*|GEMINI_CLI|CODEX_SANDBOX*|CURSOR_AGENT|OLLAMA_*|HF_TOKEN|AGY_*)
        [[ -n "${(P)v}" ]] && _tmd_markers+="$v ";;
    esac
  done
  for v in ANTHROPIC_MODEL CLAUDE_MODEL OPENAI_MODEL CODEX_MODEL GEMINI_MODEL COPILOT_MODEL AIDER_MODEL GOOSE_MODEL HERMES_MODEL OLLAMA_MODEL GROK_MODEL KIMI_MODEL QWEN_MODEL OPENCODE_MODEL CRUSH_MODEL VIBE_MODEL AMP_MODEL CLINE_MODEL DROID_MODEL LLM_MODEL MODEL_NAME MODEL; do
    [[ -n "${(P)v}" ]] && { _tmd_model="${(P)v}"; break; }
  done
}

_tmd_write() {
  print -rn -- "$1"$'\x1f'"$2"$'\x1f'"$EPOCHREALTIME"$'\x1f'"$3"$'\x1f'"$PWD"$'\x1f'"$4"$'\x1f'$'\x1f'"$_tmd_model"$'\x1f'"$_tmd_host"$'\x1f'"$_tmd_anc"$'\x1f'"$_tmd_markers"$'\x1e'$'\n' >> "$_tmd_log" 2>/dev/null
}

if [[ -o interactive ]]; then
  _tmd_scan
  unset TIERMINAL_ANC TIERMINAL_MARKERS TIERMINAL_MODEL
  autoload -Uz add-zsh-hook
  _tmd_preexec() { _tmd_cmd="$1"; _tmd_t0="$EPOCHREALTIME"; }
  _tmd_precmd() {
    local rc=$?
    [[ -n "$_tmd_cmd" ]] || return 0
    _tmd_write i "$_tmd_t0" "$rc" "$_tmd_cmd"
    _tmd_cmd=""
  }
  add-zsh-hook preexec _tmd_preexec
  add-zsh-hook precmd _tmd_precmd
elif [[ -n "$ZSH_EXECUTION_STRING" ]]; then
  if [[ -n "$TIERMINAL_ANC" ]]; then
    _tmd_anc="$(ps -o command= -p $PPID 2>/dev/null | cut -c1-160)"$'\x1d'"$TIERMINAL_ANC"
    _tmd_markers="$TIERMINAL_MARKERS" _tmd_model="$TIERMINAL_MODEL"
  else
    _tmd_scan
    export TIERMINAL_ANC="$_tmd_anc" TIERMINAL_MARKERS="$_tmd_markers" TIERMINAL_MODEL="$_tmd_model"
  fi
  typeset -g _tmd_t0="$EPOCHREALTIME"
  autoload -Uz add-zsh-hook
  _tmd_exit() { _tmd_write c "$_tmd_t0" "$?" "$ZSH_EXECUTION_STRING"; }
  add-zsh-hook zshexit _tmd_exit
fi
