#!/bin/bash
# Shared Claude Code / Codex hook: emit WezTerm user var for tab state tracking.
# Usage: claude-state.sh [running|asking|idle]
# No argument clears the state (Claude SessionEnd or Codex shell wrapper).
#
# Claude Code redirects hook stdout, so we walk /proc to find the
# ancestor PTY and write the OSC escape directly.
STATE="$1"

# Encode state as base64 (empty state -> empty value to clear the var).
if [ -n "$STATE" ]; then ENCODED=$(printf '%s' "$STATE" | base64 -w0); else ENCODED=""; fi

# Background agents run under the daemon with no controlling tty, so the
# ancestor walk below finds nothing. Their tabs display the session through
# `claude attach <id>` clients, where <id> is the first 8 chars of the
# session_id from the hook JSON on stdin. Write state to those clients'
# PTYs directly (they run in plain wezterm panes, no tmux passthrough).
JSON=""
if [[ -p /dev/stdin ]]; then
  JSON=$(cat)
fi
tmp=${JSON#*\"session_id\":\"}
if [[ "$tmp" != "$JSON" ]]; then
  sid=${tmp%%\"*}
  agent=${sid:0:8}
  found=0
  while read -r ptty cmd; do
    if [[ "$ptty" != "?" && "$cmd" == *"claude attach ${agent}"* ]]; then
      printf '\033]1337;SetUserVar=%s=%s\007' \
        claude_state "$ENCODED" > "/dev/$ptty" 2>/dev/null
      found=1
    fi
  done < <(ps -axo tty=,command=)
  [ "$found" = "1" ] && exit 0
fi

# Walk up the process tree to find the first ancestor with a PTY on stdout.
TTY=""
pid=$PPID
while [ "$pid" != "1" ] && [ -n "$pid" ]; do
  fd=$(readlink /proc/$pid/fd/1 2>/dev/null)
  if [[ "$fd" == /dev/pts/* ]]; then TTY="$fd"; break; fi
  pid=$(cut -d' ' -f4 /proc/$pid/stat 2>/dev/null)
done
[ -z "$TTY" ] && exit 0

# Emit OSC 1337 SetUserVar, with tmux DCS passthrough if needed.
if [ -n "$TMUX" ]; then
  printf '\033Ptmux;\033\033]1337;SetUserVar=%s=%s\007\033\\' \
    claude_state "$ENCODED" > "$TTY" 2>/dev/null
else
  printf '\033]1337;SetUserVar=%s=%s\007' \
    claude_state "$ENCODED" > "$TTY" 2>/dev/null
fi
