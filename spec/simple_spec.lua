local n = require('fltnotify.manager').new({
    separator = ';x',
})

n:notify('hello world!')
vim.defer_fn(function()
    n:notify(
        'test multiline notification\nand have some spaces\n\nin between',
        vim.log.levels.WARN,
        { timeout = 1500 }
    )
end, 2000)

vim.defer_fn(function()
    n:notify(
        'in between order is not messed',
        vim.log.levels.ERROR,
        { timeout = 2000, progress = true }
    )
    n:notify('bye world!')
end, 2500)
