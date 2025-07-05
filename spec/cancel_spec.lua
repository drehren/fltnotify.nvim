local m = require('fltnotify.manager').new({
    timeout = 1000,
    anchor = 'SW',
})

m:create_cancelation_command('FltSpecCancel')

local function check_cancel(name, n)
    vim.defer_fn(function()
        if m:notification_visible(n) then
            print(name .. ' not cancelled')
        end
    end, m:timeout() / 2 + 30)
end

local pi2
local i = m:create_notification({
    message = 'test progress',
    level = vim.log.levels.ERROR,
    progress = true,
    cancel = function()
        print('i was cancelled')
        pi2 = m:create_notification({
            message = 'special long cancel\nthis is detail of message',
            progress = true,
            cancel = function()
                local pi2_c = m:create_notification({
                    message = 'cancelling special long cancel',
                    progress = true,
                })

                vim.defer_fn(function()
                    m:notification_set_progress(pi2_c, 'done')
                    check_cancel('pi2_c', pi2_c)
                    check_cancel('pi2', pi2)
                    vim.defer_fn(function()
                        m:destroy()
                    end, 1400)
                end, 2000)
                return pi2_c
            end,
        })
        m:notification_show(pi2)
    end,
})
m:notification_show(i)

vim.defer_fn(function()
    vim.cmd('FltSpecCancel test\\ progress')
    check_cancel('i', i)
end, 2000)

vim.defer_fn(function()
    -- vim.cmd('FltSpecCancel special\\ long\\ cancel')
    m:notification_progress_cancel(pi2)
end, 5000)
