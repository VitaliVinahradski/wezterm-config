local wezterm = require("wezterm")
local theme = require("theme")

local M = {}

local STATE_COLORS = {
  asking  = theme.peach,
  running = theme.blue,
  idle    = theme.toxic,
}

function M.update_border(window)
  local dominated = "idle"

  for _, tab in ipairs(window:mux_window():tabs()) do
    for _, pane in ipairs(tab:panes()) do
      local state = pane:get_user_vars().claude_state
      if state == "asking" then
        dominated = "asking"
        break
      elseif state == "running" and dominated ~= "asking" then
        dominated = "running"
      end
    end
    if dominated == "asking" then break end
  end

  local key = "border_state_" .. tostring(window:window_id())
  local prev = (wezterm.GLOBAL.border_states or {})[key]
  if prev == dominated then return end

  wezterm.GLOBAL.border_states = wezterm.GLOBAL.border_states or {}
  wezterm.GLOBAL.border_states[key] = dominated

  local overrides = window:get_config_overrides() or {}
  overrides.window_frame = theme.make_window_frame(STATE_COLORS[dominated] or theme.toxic)
  window:set_config_overrides(overrides)
end

return M
