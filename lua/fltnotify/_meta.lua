---@meta

---@module 'fltanim.animations'

--- Notification
---@alias fltnotify.notification integer

--- Progress values
---@alias fltnotify.progress_value number|boolean|'done'

--- Notification options
---@class fltnotify.notification_opts
--- Notification message
---
--- First line will be treated as message title, additional lines are
--- considered message details.
---@field message? string
--- Notification level
---@field level? vim.log.levels
--- Notification timeout
---
--- Use to define a custom timeout. If `false`, the notification must be
--- manually removed.
---@field timeout? number|false
--- Notification progress
---
--- Use to show or end a progress notification. A progress notification
--- ends when `'done'` is used as value.
---
--- A progress notification is not subject to timeout, it must be manually
--- removed.
---
--- Use `false` to remove progress state.
---@field progress? fltnotify.progress_value|false
--- Notification progress cancellation
---
--- Callback to notify that the user wants to cancel the progress operation.
--- Only valid for 'progress' notifications.
--- The callback can return a new notification id, which will be used to
--- end this current notification. This may be useful when cancellation can
--- take a while as well.
---
--- Pass `false` to remove cancellation.
---@field cancel? function|false

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
--- Width of the progress label, for horizontal animations
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
--- Defines label and highlight for each log level
---@field level? table<vim.log.levels, fltnotify.level_highlight>
--- If set, defines the system wide notification cancellation command name
---
--- Use this to automatically create a command. Defaults to `nil`
---@field cancel_command_name? string

---@type fltnotify.config
vim.g.fltnotify_config = vim.g.fltnotify_config
