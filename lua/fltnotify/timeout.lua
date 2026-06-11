---@class fltnotify.item_timeout
---@field id fltnotify.notification
---@field val number
local H = {}
H.__index = H

--@param id fltnotify.notification
---@param val number
function H:new(id, val)
    return setmetatable({ id = id, val = val }, H)
end

return H
