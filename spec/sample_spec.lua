local tests = {
    { 'hello' },
    { 'hi again', vim.log.levels.WARN },
    { 'I will add more text', vim.log.levels.DEBUG },
    { 'Some\nmultiline\nnotification', vim.log.levels.ERROR },
    {
        'this will be a long notification so we are sure this gets resized as it should',
    },
    {
        'some more notifications to check for ordering',
        nil,
        { progress = true },
    },
    { 'But I think this one ....' },
    { '                     .... will be different' },
}

local nm = require('fltnotify.manager').new({
    anchor = 'NE',
    border = 'bold',
})

for i, t in ipairs(tests) do
    vim.defer_fn(function()
        nm:notify(unpack(t))
    end, i * 694.2)
end

-- make some to stay after a while
local n1 = nm:create_notification({ message = 'I will stay..', timeout = 1500 })
local n2 = nm:create_notification({ message = 'I should be autoremoved' })
nm:notification_show(n1)
nm:notification_show(n2)

vim.defer_fn(function()
    nm:notification_set_timeout(n1, false)
end, 1000)

vim.defer_fn(function()
    nm:notification_set_opts(n1, {
        message = 'ok, too much now, will go bye!',
        timeout = 2000,
    })
end, math.max(#tests * 694.2, 8000))
