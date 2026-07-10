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

-- The wezterm CLI lives next to the GUI binary; needed for kill-pane since
-- the mux Lua API has no pane kill and CloseCurrentTab via perform_action
-- only targets the window's active tab, not an arbitrary pane.
local WEZTERM_BIN = wezterm.executable_dir .. "/wezterm"

-- Pane ids of agent tabs opened by the last press. Module-level mutable
-- state (same pattern as health.lua); a config reload resets it, in which
-- case the next press opens fresh tabs instead of closing the old ones.
local opened_panes = {}

-- Kill the panes opened by the previous press. Killing the pane only ends
-- the `claude attach` client (detach); the background agent keeps running.
-- Returns how many panes were actually closed (0 if all were closed by hand).
local function detach_agents(window)
  local closed = 0
  for _, pane_id in ipairs(opened_panes) do
    local ok = wezterm.run_child_process({
      WEZTERM_BIN, "cli", "kill-pane", "--pane-id", tostring(pane_id),
    })
    if ok then
      closed = closed + 1
    end
  end
  opened_panes = {}
  if closed > 0 then
    toast(window, "Detached " .. closed .. " agent tab" .. (closed == 1 and "" or "s"), 3000)
  end
  return closed
end

-- Toggle: first press opens every active background agent in its own tab of
-- the current window (enumerated via `claude agents --json`, connected with
-- `claude attach <id>`); second press detaches them all by killing the
-- attach panes. If every tracked tab was already closed by hand, the press
-- falls through and opens fresh tabs.
local function open_agents(window, _pane)
  if #opened_panes > 0 and detach_agents(window) > 0 then
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
          table.insert(opened_panes, spawned_pane:pane_id())
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
