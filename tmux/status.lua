local wezterm = require("wezterm")
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

return M
