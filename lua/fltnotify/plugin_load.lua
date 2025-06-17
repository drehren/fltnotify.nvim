-- Handle plugin initialization, to be used when user has surely configured
-- this plugin

if vim.g.fltnotify_config.replace_system_notification then
    local fltnotify = require('fltnotify')
    vim.notify = fltnotify.notify
    vim.notify_once = fltnotify.notify_once

    vim.api.nvim_create_user_command('FltNotifyLog', function()
        fltnotify.view_notification_log()
    end, {
        count = 0,
        desc = [[Shows the notification log]],
    })
end

local progrok, progress = pcall(require, 'fltprogr')
if progrok then
    local fltnotify = require('fltnotify')
    fltnotify.register_progress_display(progress, progress.categories.LSP)
end
