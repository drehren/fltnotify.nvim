if vim.g.fltnotify_loaded then
    return
end

vim.g.fltnotify_loaded = true

vim.api.nvim_create_autocmd('VimEnter', {
    once = true,
    callback = function()
        require('fltnotify.plugin_load')
    end,
})
