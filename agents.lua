local wezterm = require("wezterm")

local M = {}

local HOME = os.getenv("HOME") or ""
local CLAUDE_FALLBACK_PATHS = {
  HOME .. "/.local/bin/claude",
  HOME .. "/.claude/local/claude",
  "/opt/homebrew/bin/claude",
  "/usr/local/bin/claude",
}

local function trim(value)
  if not value then
    return nil
  end
  local result = value:match("^%s*(.-)%s*$")
  return (result and #result > 0) and result or nil
end

local function resolve_claude_from_path()
  local handle = io.popen("command -v claude 2>/dev/null")
  if not handle then
    return nil
  end
  local result = trim(handle:read("*a"))
  handle:close()
  return result
end

local function resolve_claude_from_fallback()
  for _, path in ipairs(CLAUDE_FALLBACK_PATHS) do
    local f = io.open(path, "r")
    if f then
      f:close()
      return path
    end
  end
  return nil
end

-- Resolve the `claude` binary path once at config load.
-- run_child_process yields across the C-call boundary at require time, so use
-- io.popen (synchronous) first, then a fixed fallback list.
M.bin = resolve_claude_from_path() or resolve_claude_from_fallback()

local function toast(window, message, timeout_ms)
  window:toast_notification("WezTerm", message, nil, timeout_ms or 4000)
end

-- file:// URL for OSC 7 (percent-encode anything outside the unreserved set)
local function file_url(path)
  local encoded = path:gsub("([^%w/._~%-])", function(c)
    return string.format("%%%02X", string.byte(c))
  end)
  return "file://" .. wezterm.hostname() .. encoded
end

-- The wezterm CLI lives next to the GUI binary; needed for kill-pane since
-- the mux Lua API has no pane kill and CloseCurrentTab via perform_action
-- only targets the window's active tab, not an arbitrary pane.
local WEZTERM_BIN = wezterm.executable_dir .. "/wezterm"

-- True if the pane's foreground process looks like `claude attach ...`.
-- Loose argv match (any element containing "claude" plus an "attach"
-- element) because npm installs run as node with the cli.js path in argv.
-- Non-local panes (e.g. tmux CC domain) return nil info and never match.
local function is_attach_pane(pane)
  local info = pane:get_foreground_process_info()
  if not info or type(info.argv) ~= "table" then
    return false
  end
  local claude, attach = false, false
  for _, arg in ipairs(info.argv) do
    if arg:find("claude", 1, true) then
      claude = true
    elseif arg == "attach" then
      attach = true
    end
  end
  return claude and attach
end

-- Agent tabs are not tracked in Lua state: a config reload would build a
-- fresh interpreter, wipe the list, and orphan the open tabs. Instead each
-- press derives the set live by scanning every mux pane, so reloads and
-- hand-closed tabs can never desync the toggle.
local function find_attach_panes()
  local panes = {}
  for _, mux_window in ipairs(wezterm.mux.all_windows()) do
    for _, tab in ipairs(mux_window:tabs()) do
      for _, pane in ipairs(tab:panes()) do
        if is_attach_pane(pane) then
          table.insert(panes, pane)
        end
      end
    end
  end
  return panes
end

-- Kill the attach panes. Killing the pane only ends the `claude attach`
-- client (detach); the background agent keeps running.
local function detach_agents(window, panes)
  local closed = 0
  for _, pane in ipairs(panes) do
    local ok = wezterm.run_child_process({
      WEZTERM_BIN, "cli", "kill-pane", "--pane-id", tostring(pane:pane_id()),
    })
    if ok then
      closed = closed + 1
    end
  end
  if closed > 0 then
    toast(window, "Detached " .. closed .. " agent tab" .. (closed == 1 and "" or "s"), 3000)
  end
end

-- Toggle: first press opens every active background agent in its own tab of
-- the current window (enumerated via `claude agents --json`, connected with
-- `claude attach <id>`); second press detaches every pane whose foreground
-- process is `claude attach`, wherever it lives — including ones started by
-- hand in a shell.
local function open_agents(window, _pane)
  local attach_panes = find_attach_panes()
  if #attach_panes > 0 then
    detach_agents(window, attach_panes)
    return
  end

  if not M.bin then
    toast(window, "claude binary not found on PATH")
    return
  end

  local ok, stdout, stderr = wezterm.run_child_process({ M.bin, "agents", "--json" })
  if not ok then
    toast(window, "`claude agents --json` failed: " .. (trim(stderr) or "unknown error"), 5000)
    return
  end

  local parsed_ok, agents = pcall(wezterm.json_parse, stdout)
  if not parsed_ok or type(agents) ~= "table" then
    toast(window, "Could not parse `claude agents --json` output", 5000)
    return
  end

  local mux_window = window:mux_window()
  local count = 0
  for _, agent in ipairs(agents) do
    if type(agent) == "table" and agent.id then
      local spawn_opts = { args = { M.bin, "attach", agent.id } }
      if agent.cwd and #agent.cwd > 0 then
        spawn_opts.cwd = agent.cwd
      end
      local tab_ok, tab, spawned_pane = pcall(mux_window.spawn_tab, mux_window, spawn_opts)
      if tab_ok and tab then
        if agent.name and #agent.name > 0 then
          tab:set_title(agent.name)
        end
        if spawned_pane then
          -- The Claude TUI never emits OSC 7 and the attach client's process
          -- cwd is $HOME, so WezTerm's cwd divining gives splits from agent
          -- tabs the wrong directory. Inject OSC 7 once to pin the pane cwd
          -- to the agent's project dir (OSC 7 takes precedence over divining).
          if spawn_opts.cwd then
            spawned_pane:inject_output("\x1b]7;" .. file_url(spawn_opts.cwd) .. "\x1b\\")
          end
        end
        count = count + 1
      end
    end
  end

  if count == 0 then
    toast(window, "No background agents to open")
  else
    toast(window, "Opened " .. count .. " agent tab" .. (count == 1 and "" or "s"), 3000)
  end
end

function M.keys()
  return {
    { key = "g", mods = "CTRL|SHIFT", action = wezterm.action_callback(open_agents) },
  }
end

return M
