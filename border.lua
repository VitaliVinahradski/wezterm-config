local wezterm = require("wezterm")
local theme = require("theme")

local M = {}

local ESCALATION_SECS = 15

local STATE_COLORS = {
  asking  = theme.peach,
  running = theme.blue,
  idle    = theme.toxic,
}

function M.update_border(window)
  local dominated = "idle"
  local any_escalated = false

  for _, tab in ipairs(window:mux_window():tabs()) do
    for _, pane in ipairs(tab:panes()) do
      local state = pane:get_user_vars().claude_state
      if state == "asking" then
        dominated = "asking"
        local key = tostring(pane:pane_id())
        local since = (wezterm.GLOBAL.asking_since or {})[key]
        if since and (os.time() - since) >= ESCALATION_SECS then
          any_escalated = true
        end
      elseif state == "running" and dominated ~= "asking" then
        dominated = "running"
      end
    end
  end

  local color = STATE_COLORS[dominated] or theme.toxic
  if dominated == "asking" and any_escalated then
    color = theme.red
  end

  local key = "border_state_" .. tostring(window:window_id())
  local cache_val = dominated .. (any_escalated and "_esc" or "")
  local prev = (wezterm.GLOBAL.border_states or {})[key]
  if prev == cache_val then return end

  wezterm.GLOBAL.border_states = wezterm.GLOBAL.border_states or {}
  wezterm.GLOBAL.border_states[key] = cache_val

  local overrides = window:get_config_overrides() or {}
  overrides.window_frame = theme.make_window_frame(color)
  window:set_config_overrides(overrides)
end

return M
