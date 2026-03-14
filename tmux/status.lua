local wezterm = require("wezterm")
local act = wezterm.action
local core = require("tmux.core")
local theme = require("theme")

local M = {}

function M.update_left_status(window, pane)
  local bar_bg = theme.base
  local bg, fg, label

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

  window:set_left_status(wezterm.format({
    { Background = { Color = bg } },
    { Foreground = { Color = fg } },
    { Text = string.format(" %s  %s ", theme.ICON_TERMINAL, label) },
    { Background = { Color = bar_bg } },
    { Foreground = { Color = bg } },
    { Text = theme.SOLID_RIGHT },
  }))
end

function M.keys()
  return {
    {
      key = "a",
      mods = "CTRL|SHIFT",
      action = wezterm.action_callback(function(window, pane)
        if not core.bin then
          window:perform_action(
            act.InputSelector({
              title = "Attach tmux session",
              choices = { { id = "", label = "tmux not found" } },
              action = wezterm.action_callback(function() end),
            }),
            pane
          )
          return
        end
        local success, stdout = wezterm.run_child_process({
          core.bin, "list-sessions", "-F",
          "#{session_name}|#{session_windows} wins, created #{t:session_created}",
        })
        local choices = {}
        if success then
          for line in stdout:gmatch("[^\r\n]+") do
            local name = line:match("^([^|]+)")
            table.insert(choices, { id = name, label = line:gsub("|", " — ") })
          end
        end
        if #choices == 0 then
          table.insert(choices, { id = "", label = "No tmux sessions found" })
        end
        window:perform_action(
          act.InputSelector({
            title = "Attach tmux session",
            choices = choices,
            action = wezterm.action_callback(function(inner_window, inner_pane, id, label)
              if id and id ~= "" then
                inner_window:perform_action(
                  act.SpawnCommandInNewTab({
                    domain = { DomainName = "local" },
                    args = { core.bin, "-CC", "attach", "-t", id },
                  }),
                  inner_pane
                )
              end
            end),
          }),
          pane
        )
      end),
    },
  }
end

return M
