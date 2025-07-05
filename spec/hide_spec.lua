local m = require('fltnotify.manager').new({
    timeout = 2000,
    anchor = 'SE',
    margin = { 4, 1 },
})

local n = {
    m:create_notification({
        message = 'a long notification to awkward all the other ones... and check behavior',
    }),
    m:create_notification({
        message = 'hello',
        timeout = 800,
    }),
    m:create_notification({
        message = 'bye\nnot',
        progress = true,
    }),
    m:create_notification({
        message = 'what I\nam doing',
    }),
    m:create_notification({
        message = "I'll be removed in 3",
    }),
}

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_open_win(buf, false, {
    relative = 'editor',
    row = vim.o.lines - 4,
    col = vim.o.columns - 10,
    width = 9,
    height = 1,
    border = 'none',
    fixed = true,
    style = 'minimal',
})

local emns = vim.api.nvim_create_namespace('renderspec')
local emid = vim.api.nvim_buf_set_extmark(buf, emns, 0, 0, {
    virt_text = { { '  0.000 s', 'NormalFloat' } },
})
local timer = assert(vim.uv.new_timer())
local time = vim.uv.hrtime()
timer:start(
    0,
    10,
    vim.schedule_wrap(function()
        local delta = (vim.uv.hrtime() - time) * 10e-10
        vim.api.nvim_buf_set_extmark(buf, emns, 0, 0, {
            id = emid,
            virt_text = { { ('%3.3f s'):format(delta), 'NormalFloat' } },
        })
    end)
)

for i, ni in ipairs(n) do
    vim.defer_fn(function()
        m:notification_show(ni)
    end, (i - 1) * 100)
end

if n[5] then
    for i = 2, 1, -1 do
        vim.defer_fn(function()
            m:notification_set_message(n[5], "I'll be removed in " .. i)
        end, 500 + m:timeout() / 3 * (3 - i))
    end

    vim.defer_fn(function()
        m:notification_set_message(n[5], "I'll be removed in 2")
    end, 400 + m:timeout() / 2)
    vim.defer_fn(function()
        m:notification_set_message(n[5], "I'll be removed in 1")
    end, 400 + m:timeout())
end

vim.defer_fn(function()
    m:notification_set_message(n[1], 'changed 1')
end, 1000)

if n[3] then
    vim.defer_fn(function()
        print('was cancelled')
        m:notification_set_progress(n[3], 'cancelled')
    end, 1100)
end

vim.defer_fn(function()
    timer:stop()
    vim.defer_fn(function()
        vim.api.nvim_buf_delete(buf, { force = true, unload = true })
    end, 2000)
    m:destroy()
    print('done')
end, 5000)
