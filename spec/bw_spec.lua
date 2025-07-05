---@type {[1]:string, [2]:number?, [3]:fltnotify.notification_opts?}[]
local tests = {
    { 'hello' },
    { 'hello again? is anyone there?' },
    { 'this is not good', vim.log.levels.WARN },
    {
        'multiline\nexample\nnotification',
        vim.log.levels.ERROR,
        { timeout = 1000 },
    },
    { 'this is a long notification, to check what happens if there is one' },
    { 'Just one more to go...' },
    { "                   ... and now we're out" },
}

local m = require('fltnotify.manager').new({
    anchor = 'NW',
    separator = '+',
    border = 'solid',
})

local totaltime = 5000
for i, t in ipairs(tests) do
    local msg, lvl, opts = unpack(t)
    if not opts then
        opts = {}
    end
    if not opts.timeout then
        opts.timeout = totaltime - (i - 1) * (totaltime / #tests)
    end
    m:notify(msg, lvl, opts)
end
