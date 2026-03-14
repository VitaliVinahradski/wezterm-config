# Visual Improvements Plan

Three highest-impact upgrades for the CLI beauty contest (Claude operator setup).

## 1. Powerline tab bar with Claude state icons -- DONE

Shipped. Remaining polish:

- [ ] Unseen output dot missing on styled inactive tabs (claude state early-returns before the unseen check)

---

## 2. Styled status bar as a cohesive info ribbon -- DONE

Shipped. Scope changed from plan: dropped `HH:MM` clock, added pane count + zoom widget instead.

Remaining polish:

- [ ] Double space between icon and label in left status (`tmux/status.lua` line 26) — every other format string uses single space

---

## 3. Background layers + refined window chrome -- DONE

Shipped. Two-layer background (solid base at 0.93 opacity + radial vignette to mantle at 0.35 opacity). Reactive border via `border.lua` with `set_config_overrides` and GLOBAL state caching. `theme.make_window_frame()` is the single source of truth for frame structure.

---

## Implementation order

1. ~~Tab bar (biggest visual delta, self-contained in theme + claude)~~ Done
2. ~~Status ribbon (completes the bottom chrome)~~ Done
3. ~~Background + border (finishing touch)~~ Done
