local wezterm = require("wezterm")
local act = wezterm.action
local core = require("tmux.core")
local theme = require("theme")

local M = {}

local function left_status_elements(bg, fg, label)
  local bar_bg = theme.base
  return {
    { Background = { Color = bg } },
    { Foreground = { Color = fg } },
    { Text = string.format(" %s  %s ", theme.ICON_TERMINAL, label) },
    { Background = { Color = bar_bg } },
    { Foreground = { Color = bg } },
    { Text = theme.SOLID_RIGHT },
  }
end

function M.update_left_status(window, pane)
  local bg
  local fg
  local label

  if core.detect(pane) then
    bg = theme.green
    fg = theme.base
    label = "tmux"
  else
    local proc = pane:get_foreground_process_name() or ""
    label = proc:match("([^/]+)$") or "shell"
    bg = theme.surface
    fg = theme.subtext
  end

  window:set_left_status(wezterm.format(left_status_elements(bg, fg, label)))
end

local function parse_session_choices(stdout)
  local choices = {}
  for line in stdout:gmatch("[^\r\n]+") do
    local name = line:match("^([^|]+)")
    table.insert(choices, { id = name, label = line:gsub("|", " — ") })
  end
  return choices
end

local function show_selector(window, pane, choices, on_select)
  window:perform_action(
    act.InputSelector({
      title = "Attach tmux session",
      choices = choices,
      action = on_select,
    }),
    pane
  )
end

function M.keys()
  local attach_session = wezterm.action_callback(function(inner_window, inner_pane, id, _label)
    if id and id ~= "" then
      inner_window:perform_action(
        act.SpawnCommandInNewTab({
          domain = { DomainName = "local" },
          args = { core.bin, "-CC", "attach", "-t", id },
        }),
        inner_pane
      )
    end
  end)

  local noop = wezterm.action_callback(function() end)

  return {
    {
      key = "a",
      mods = "CTRL|SHIFT",
      action = wezterm.action_callback(function(window, pane)
        if not core.bin then
          show_selector(window, pane, { { id = "", label = "tmux not found" } }, noop)
          return
        end

        local success, stdout = wezterm.run_child_process({
          core.bin,
          "list-sessions",
          "-F",
          "#{session_name}|#{session_windows} wins, created #{t:session_created}",
        })

        local choices = success and parse_session_choices(stdout) or {}
        if #choices == 0 then
          table.insert(choices, { id = "", label = "No tmux sessions found" })
        end

        show_selector(window, pane, choices, attach_session)
      end),
    },
  }
end

return M
