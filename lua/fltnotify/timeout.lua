local M = {}

---@class fltnotify.item_timeout
---@field id fltnotify.notification
---@field val number

---@param heap fltnotify.item_timeout[]
---@param value fltnotify.item_timeout
function M.timelist_push(heap, value)
    local idx = #heap + 1
    heap[idx] = value
    if idx == 1 then
        return
    end
    local pidx = math.floor(idx / 2)
    while pidx > 0 and heap[pidx].val > heap[idx].val do
        heap[pidx], heap[idx] = heap[idx], heap[pidx]
        idx = pidx
        pidx = math.floor(idx / 2)
    end
end

---@param heap fltnotify.item_timeout[]
---@param value fltnotify.item_timeout
---@return fltnotify.item_timeout
function M.timelist_replace(heap, value)
    assert(#heap > 0, 'list is empty')
    local val = heap[1]
    heap[1] = value
    local idx = 1
    while heap[idx] do
        local lidx = idx * 2
        local ridx = idx * 2 + 1
        local cidx
        if heap[ridx] and heap[lidx] then
            if heap[ridx].val < heap[lidx].val then
                cidx = ridx
            else
                cidx = lidx
            end
        else
            if heap[lidx] then
                cidx = lidx
            else
                break
            end
        end
        if heap[idx].val > heap[cidx].val then
            heap[idx], heap[cidx] = heap[cidx], heap[idx]
            idx = cidx
        else
            break
        end
    end
    return val
end

---@param heap fltnotify.item_timeout[]
---@return fltnotify.item_timeout
function M.timelist_pop(heap)
    if #heap == 1 then
        return table.remove(heap)
    end
    return M.timelist_replace(heap, table.remove(heap))
end

---@param timer uv.uv_timer_t
---@param timelist fltnotify.item_timeout[]
---@return fltnotify.item_timeout?
function M.update_timelist(timer, timelist)
    local cur = timelist[1]
    if cur then
        local t = cur.val - timer:get_due_in()
        for i = 1, #timelist do
            timelist[i].val = timelist[i].val - t
        end
    end
    return cur
end

local tmcache = setmetatable({}, { __mode = 'k' })
---@param timer uv.uv_timer_t
---@param timelist fltnotify.item_timeout[]
function M.restart_timer(timer, timelist, callback)
    if not timelist[1] then
        if timer:is_active() then
            timer:stop()
        end
        return
    end
    if not tmcache[callback] then
        local function timedone()
            local popedids = {}
            local t = M.timelist_pop(timelist)
            callback(t.id)
            popedids[t.id] = true
            for _, v in ipairs(timelist) do
                v.val = v.val - t.val
            end
            while #timelist > 0 and timelist[1].val <= 0 do
                t = M.timelist_pop(timelist)
                if not popedids[t.id] then
                    callback(t.id)
                    popedids[t.id] = true
                end
            end
            if timelist[1] then
                timer:start(timelist[1].val, 0, timedone)
            end
        end
        tmcache[callback] = timedone
    end
    timer:start(timelist[1].val, 0, tmcache[callback])
end

---@param timer uv.uv_timer_t
---@param timelist fltnotify.item_timeout[]
---@param timeout fltnotify.item_timeout
function M.add_timeout(timer, timelist, timeout, callback)
    if
        timelist[1]
        and timeout.id == timelist[1].id
        and timeout.val == timelist[1].val
    then
        return
    end
    local cur = M.update_timelist(timer, timelist)
    if cur and cur.id == timeout.id then
        M.timelist_replace(timelist, timeout)
    else
        M.timelist_push(timelist, timeout)
    end
    if cur and cur.val == timelist[1].val then
        return
    end
    M.restart_timer(timer, timelist, callback)
end

return M
