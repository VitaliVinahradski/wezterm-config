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

-- Workaround: WezTerm's tmux CC handler uses resize-window but never sends
-- refresh-client -C, so the CC client keeps default-size (80x24). New tmux
-- windows inherit that wrong size. Sync CC client dimensions on window resize.
function M.sync_cc_client_size(window, pane)
  if not core.bin or not core.is_cc(pane) then return end
  local tab = pane:tab()
  if not tab then return end
  local size = tab:get_size()
  if not size or size.cols == 0 or size.rows == 0 then return end
  local dim = string.format("%dx%d", size.cols, size.rows)
  local key = "cc_size_" .. tostring(window:window_id())
  if (wezterm.GLOBAL.cc_synced or {})[key] == dim then return end
  wezterm.GLOBAL.cc_synced = wezterm.GLOBAL.cc_synced or {}
  wezterm.GLOBAL.cc_synced[key] = dim
  wezterm.run_child_process({ core.bin, "refresh-client", "-C", dim })
end

return M
