#!/bin/zsh
# Shared Claude Code / Codex hook: emit WezTerm user var for tab state tracking (macOS).
# Usage: claude-state.zsh [running|asking|idle]
# No argument clears the state (Claude SessionEnd or Codex shell wrapper).
#
# Claude Code redirects hook stdout, so we walk the process tree
# via ps to find the ancestor PTY and write the OSC escape directly.
STATE="$1"

# Encode state as base64 (empty state -> empty value to clear the var).
[[ -n "$STATE" ]] && ENCODED=$(printf '%s' "$STATE" | base64 | tr -d '\n') || ENCODED=""

# Background agents run under the daemon with no controlling tty, so the
# ancestor walk below finds nothing. Their tabs display the session through
# `claude attach <id>` clients, where <id> is the first 8 chars of the
# session_id from the hook JSON on stdin. Write state to those clients'
# PTYs directly (they run in plain wezterm panes, no tmux passthrough).
JSON=""
if [[ -p /dev/stdin ]]; then
  IFS= read -r -t 2 -d "" JSON
fi
tmp=${JSON#*\"session_id\":\"}
if [[ "$tmp" != "$JSON" ]]; then
  agent=${${tmp%%\"*}[1,8]}
  found=0
  ps -axo tty=,command= | while read -r ptty cmd; do
    if [[ "$ptty" != "??" && "$cmd" == *"claude attach ${agent}"* ]]; then
      printf '\033]1337;SetUserVar=%s=%s\007' \
        claude_state "$ENCODED" > "/dev/$ptty" 2>/dev/null
      found=1
    fi
  done
  (( found )) && exit 0
fi

# Walk up the process tree to find the first ancestor with a PTY.
TTY=""
pid=$PPID
while (( pid > 1 )); do
  info=$(ps -o tty=,ppid= -p "$pid" 2>/dev/null)
  tty_name=${${(z)info}[1]}
  next_pid=${${(z)info}[2]}
  if [[ -n "$tty_name" && "$tty_name" != "??" ]]; then
    TTY="/dev/$tty_name"
    break
  fi
  pid=$next_pid
done
[[ -z "$TTY" ]] && exit 0

# Emit OSC 1337 SetUserVar, with tmux DCS passthrough if needed.
if [[ -n "$TMUX" ]]; then
  printf '\033Ptmux;\033\033]1337;SetUserVar=%s=%s\007\033\\' \
    claude_state "$ENCODED" > "$TTY" 2>/dev/null
else
  printf '\033]1337;SetUserVar=%s=%s\007' \
    claude_state "$ENCODED" > "$TTY" 2>/dev/null
fi
