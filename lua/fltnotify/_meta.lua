---@meta

---@module 'fltanim.symbols'

--- Notification
---@alias fltnotify.notification integer

--- Progress values
---@alias fltnotify.progress_value number|true|'done'

--- Notification options
---@class fltnotify.notification_data
---@field progress? fltnotify.progress_value
---@field timeout? number|false
---@field level? vim.log.levels

--- Level visualization
---@class fltnotify.level_highlight
---@field label? string Level label
---@field hl_group? string|integer Level highlight

---@class fltnotify.progress_config
--- Indeterminate progress visualization
---@field indeterminate? fltanim.animations
--- Valued progress visualization
---@field determinate? fltanim.animations
--- Animation frames per second
---@field fps? number
--- Width of the progress label, used for `'line'` and `'bounce'` types
---@field width? number

---@class fltnotify.config
--- Time in milliseconds before removing a notification
---@field timeout? number
--- Notification position in screen
---@field anchor? 'NW'|'NE'|'SW'|'SE'
--- Notification window border. Defaults to `vim.o.winborder`
---@field border? ''|'bold'|'none'|'single'|'double'|'rounded'|'solid'|'shadow'|string[]
--- Shows this title. Defaults to empty
---@field title? string
--- Sets the title position. Defaults to 'left'
---@field title_pos? 'center'|'left'|'right'
--- Visual notification separator. Defaults to `"─"`
---@field separator? string
--- Sets the margin from the window edge in a (row, col) tuple.
--- Defaults to (1, 1)
---@field margin? { [1]: number, [2]: number }
--- Configures progress animation
---@field progress_animation? fltnotify.progress_config
--- Set to `true` to use this plugin to display notifications, defaults to `false`
---@field replace_system_notification? boolean
--- Defines label and highligth for each log level
---@field level? table<vim.log.levels, fltnotify.level_highlight>

---@type fltnotify.config
vim.g.fltnotify_config = vim.g.fltnotify_config
