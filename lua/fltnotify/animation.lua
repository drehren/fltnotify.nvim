local ok, anim = pcall(require, 'fltanim')
if ok then
    return anim
else
    return {
        new = function()
            ---@class fltnanim.manager
            local mgr = {
                add = function()
                    vim.notify_once(
                        '[fltnotify] please install fltanim plugin use animated progress'
                    )
                end,
                pause = function() end,
                paused = function() end,
                unpause = function() end,
                stop = function() end,
                remove = function() end,
            }
            return mgr
        end,
    }
end
