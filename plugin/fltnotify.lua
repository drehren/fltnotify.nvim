if vim.g.fltnotify_loaded then
    return
end

vim.g.fltnotify_loaded = true

if not vim.g.fltnotify_config then
    -- this probably means we are being loaded by a plugin manager that loads
    -- plugin folder first.. sigh.. 
    return
end

-- To keep the initialization code that should be here consistent, we'll just
-- load a module to handle this

if not package.loaded['fltnotify.plugin_load'] then
    require('fltnotify.plugin_load')
end
