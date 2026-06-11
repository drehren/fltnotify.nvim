---@module 'bit'

local trem = table.remove
---@type fun(value:number, shift:integer):integer
local brshift = require('bit').rshift

---@class fltnotify.simple_heap<T> : { [integer]: T }
---@field private _cmp fun(lhs: T, rhs: T): integer
local H = {}
H.__index = H

--- Pushes a value into the heap
---@param value T Value to add
function H:push(value)
    local i = #self + 1
    self[i] = value
    if i == 1 then
        return
    end
    local nexti = brshift(i, 1)
    while nexti > 0 and not self._cmp(self[nexti], self[i]) do
        self[nexti], self[i] = self[i], self[nexti]
        i = nexti
        nexti = brshift(i, 1)
    end
end

--- Pops the first value from the heap
---@return T value The first value
function H:pop()
    if #self == 1 then
        return trem(self)
    end
    return self:replace(trem(self))
end

--- Pops the first value and pushes the specified value
--- The heap must have at least one value
---@param value T Value to add
---@return T value The first value
function H:replace(value)
    assert(#self > 0, 'heap is empty')
    local i = 0
    local oldval = self[i + 1]
    self[i + 1] = value
    local idx = 1
    while self[i + idx] do
        local lidx = idx * 2 + i
        local ridx = idx * 2 + 1 + i
        local cidx
        if self[ridx] and self[lidx] then
            if self._cmp(self[ridx], self[lidx]) then
                cidx = ridx
            else
                cidx = lidx
            end
        else
            if self[lidx] then
                cidx = lidx
            else
                break
            end
        end
        local qidx = i + idx
        if not self._cmp(self[qidx], self[cidx]) then
            self[qidx], self[cidx] = self[cidx], self[qidx]
            idx = cidx - i
        else
            break
        end
    end
    return oldval
end

--- Re-heaps the list
function H:reheap()
    for i = 2, #self do
        local pidx = brshift(i, 1)
        while pidx > 0 and not self._cmp(self[pidx], self[i]) do
            self[pidx], self[i] = self[i], self[pidx]
            i = pidx
            pidx = brshift(i, 1)
        end
    end
end

--- First value according to comparer
---@return T?
function H:front()
    return self[1]
end

---@generic T
---@param cmp? fun(lhs: T, rhs: T): boolean
---@return fltnotify.simple_heap<T>
function H:new(cmp)
    ---@type fltnotify.simple_heap<T>
    local h = {
        _cmp = cmp or function(l, r)
            return l < r
        end,
    }
    return setmetatable(h, self)
end

return H
