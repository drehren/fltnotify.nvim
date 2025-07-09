local manager

---@return fltnotify.manager
local function get_manager()
    if not manager then
        manager = require('fltnotify.manager').new(vim.g.fltnotify_config)
        if vim.g.fltnotify_config.cancel_command_name then
            manager:create_cancelation_command(
                vim.g.fltnotify_config.cancel_command_name
            )
        end
    end
    return manager
end

---@class fltnotify.api
local M = {}

--- Displays a notification to the user.
---@param msg string Content of the notification to show to the user.
---@param level? vim.log.levels One of the values from `vim.log.levels`.
---@param opts? fltnotify.notification_opts Notification options.
function M.notify(msg, level, opts)
    get_manager():notify(msg, level, opts)
end

--- Displays a notification only one time.
---@param msg string Content of the notification to show to the user.
---@param level? vim.log.levels One of the values from `vim.log.levels`.
---@param opts? fltnotify.notification_opts Notification options.
function M.notify_once(msg, level, opts)
    get_manager():notify_once(msg, level, opts)
end

--- Creates a new notification.
---
--- The created notification defaults to:
--- - message: `""`
--- - level: `vim.log.levels.INFO`
--- - progress: `false`
--- - timeout: `vim.g.notification_config.timeout`
--- - cancel: `nil`
---
--- To display the notification, use [notification_display](lua://fltnotify.api.notification_display).
---@param opts? fltnotify.notification_opts Notification content.
---@return fltnotify.notification
function M.create_notification(opts)
    return get_manager():create_notification(opts)
end

--- Sets the notification data
---
--- To display the notification, use [notification_display](lua://fltnotify.api.notification_display).
---@param notification fltnotify.notification
---@param data { message?: string, timeout?: number|false, progress?: number|true|'done', level?: vim.log.levels }
function M.notification_set_data(notification, data)
    get_manager():notification_set_opts(notification, data)
end

--- Set the notification message.
---@param notification fltnotify.notification Notification to update
---@param msg string New message.
function M.notification_set_message(notification, msg)
    get_manager():notification_set_message(notification, msg)
end

--- Set the notification timeout.
---
--- To create a persistent notification, pass `false`.
---@param notification fltnotify.notification Notification to update.
---@param timeout number|false New timeout.
function M.notification_set_timeout(notification, timeout)
    get_manager():notification_set_timeout(notification, timeout)
end

--- Set the notification progress.
---
--- The value range is 0.0-1.0.
--- To create an indeterminate progress, pass `true`.
--- To signal the end of the progress, pass `'done'`.
--- To stop progress display, pass `false`.
---@param notification fltnotify.notification Notification to update.
---@param progress number|boolean|'done' Progress value, or `true` or `false`.
function M.notification_set_progress(notification, progress)
    get_manager():notification_set_progress(notification, progress)
end

--- Cancel a cancellable notification.
--- @param notification fltnotify.notification
function M:notification_progress_cancel(notification)
    get_manager():notification_progress_cancel(notification)
end

--- Set the notification level
---@param notification fltnotify.notification Notification to update.
---@param level vim.log.levels New level.
function M.notification_set_level(notification, level)
    get_manager():notification_set_level(notification, level)
end

--- Deletes a notification.
---
--- This removes the notification and cannot be used again.
---@param notification fltnotify.notification The notification to delete.
function M.notification_delete(notification)
    get_manager():notification_delete(notification)
end

--- Displays a notification to the user.
---@param notification fltnotify.notification The notification to display.
function M.notification_display(notification)
    get_manager():notification_show(notification)
end

--- Hides a notification.
---
--- This removes the notification from the display, but it can be displayed again
--- in the same order as before.
---@param notification fltnotify.notification The notification to hide.
function M.notification_hide(notification)
    get_manager():notification_hide(notification)
end

---@enum fltnotify.view_log
M.view_log = {
    --- Displays the log in a new tab.
    'tab',
    --- Display the log in the current window.
    'window',
    --- Only retrieves the log buffer.
    'buffer',
}

--- Opens a window with or gets the notification log buffer
---
--- Defaults to open in a new tab
---@param view? fltnotify.view_log Specifies how to display the log. Defaults to `"tab"`.
function M.view_notification_log(view)
    ---@cast view -?
    view = view or 'tab'
    local logbuf = get_manager():create_notifications_log('system')
    if view == 'window' or view == 'tab' then
        if view == 'tab' then
            vim.cmd.tabnew()
        end
        vim.api.nvim_win_set_buf(0, logbuf)
    elseif view == 'buffer' then
        return logbuf
    else
        error(
            ([[expected one of 'tab', 'window', or 'buffer', got '%s']]):format(
                view
            )
        )
    end
end

---@param config fltnotify.config
function M.setup(config)
    vim.g.fltnotify_config = config or vim.g.fltnotify_config
end

---@module 'fltprogr'

local function format_progr_msg(ev)
    local progr = require('fltprogr')
    local category = ev.category
    if ev.category == progr.categories.LSP then
        category = vim.lsp.get_client_by_id(ev.client_id).name
    end
    if ev.category == progr.categories.WORK then
        category = ev.command or category
    end
    if ev.message then
        return ('[%s] %s\n%s'):format(category, ev.title, ev.message)
    else
        return ('[%s] %s'):format(category, ev.title)
    end
end

---@param registrar fltprogr.broker
---@param categories string|fltprogr.categories|(string|fltprogr.categories)[]
function M.register_progress_display(registrar, categories)
    local evs = {}
    local display = registrar.create_display({
        on_start = vim.schedule_wrap(function(event)
            if not evs[event.source] then
                evs[event.source] = M.create_notification()
            end
            local notification = evs[event.source]
            M.notification_set_data(notification, {
                message = format_progr_msg(event),
                level = event.level,
                progress = event.progress,
                cancel = event.cancel,
            })
            M.notification_display(notification)
        end),
        on_update = vim.schedule_wrap(function(event)
            local notification =
                assert(vim.tbl_get(evs, event.source), 'invalid source')
            M.notification_set_data(notification, {
                message = format_progr_msg(event),
                level = event.level,
                progress = event.progress,
            })
        end),
        on_end = vim.schedule_wrap(function(event)
            local notification =
                assert(vim.tbl_get(evs, event.source), 'invalid source')
            M.notification_set_data(notification, {
                message = format_progr_msg(event),
                progress = 'done',
                timeout = get_manager():timeout() / 2,
            })
        end),
    })
    registrar.display_register(display, categories)
end

return M
