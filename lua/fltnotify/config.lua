---@module 'fltanim.symbols'

---@class fltnotify.internal_progress_config
---@field indeterminate fltanim.animations
---@field determinate fltanim.animations
---@field fps number
---@field width number

---@class fltnotify.level_hl
---@field hl_group string|integer
---@field label string

---@class fltnotify.internal_config
---@field timeout number
---@field anchor 'NW'|'NE'|'SW'|'SE'
---@field border string|string[]
---@field title string?
---@field title_pos 'center'|'left'|'right'
---@field separator string
---@field margin {[1]:number, [2]:number}
---@field level table<vim.log.levels, fltnotify.level_hl>
---@field progress_animation fltnotify.internal_progress_config
---@field replace_system_notification boolean

---@type fltnotify.internal_config
local default_config = {
    timeout = 5000,
    anchor = 'NE',
    border = vim.o.winborder,
    separator = '─',
    title = nil,
    title_pos = 'left',
    margin = { 1, 1 },
    level = {
        [vim.log.levels.TRACE] = {
            label = '[T]',
            hl_group = 'DiagnosticOk',
        },
        [vim.log.levels.DEBUG] = {
            label = '[D]',
            hl_group = 'DiagnosticHint',
        },
        [vim.log.levels.INFO] = {
            label = '[I]',
            hl_group = 'DiagnosticInfo',
        },
        [vim.log.levels.WARN] = {
            label = '[W]',
            hl_group = 'DiagnosticWarn',
        },
        [vim.log.levels.ERROR] = {
            label = '[E]',
            hl_group = 'DiagnosticError',
        },
        [vim.log.levels.OFF] = {
            label = '',
            hl_group = 'Conceal',
        },
    },
    progress_animation = {
        indeterminate = 'dot_spinner',
        determinate = 'vbar_fill',
        fps = 20,
        width = 4,
    },
    replace_system_notification = false,
}

return {
    ---@param user_config fltnotify.config
    get = function(user_config)
        user_config = user_config or {}
        local cfg = vim.tbl_deep_extend('force', default_config, user_config)

        -- level table is treated as an array, merge manually
        user_config.level = user_config.level or {}
        for lvl, data in pairs(default_config.level) do
            local usr_lvl = user_config.level[lvl]
            if not usr_lvl or usr_lvl == vim.NIL then
                usr_lvl = {}
            end
            cfg.level[lvl] = vim.tbl_extend('force', data, usr_lvl)
        end

        return cfg
    end,
}
