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

-- Open every active background agent in its own tab of the current window.
-- Enumerates via `claude agents --json` (headless, no TTY) and connects each
-- with `claude attach <id>`. Always spawns fresh: re-running opens new tabs.
local function open_agents(window, _pane)
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
      local tab_ok, tab = pcall(mux_window.spawn_tab, mux_window, spawn_opts)
      if tab_ok and tab then
        if agent.name and #agent.name > 0 then
          tab:set_title(agent.name)
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
