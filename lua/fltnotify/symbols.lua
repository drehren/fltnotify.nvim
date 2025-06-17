local anim_symbols = require('fltanim.symbols')

---@param cfg fltnotify.internal_config
local function indet_symbols(cfg)
    local symbol = cfg.progress_animation.indeterminate
    local width = cfg.progress_animation.width

    return anim_symbols[symbol](width)
end

local function value_symbols(cfg)
    local symbol = cfg.progress_animation.determinate
    local width = cfg.progress_animation.width

    local symbols = anim_symbols[symbol](width)
    return symbols, 0
end

local M = {}

function M.build(cfg)
    local isym, idur = indet_symbols(cfg)
    local vsym, vdur = value_symbols(cfg)
    return { indet = isym, deter = vsym }, { indet = idur, deter = vdur }
end

return M
