---@module 'luassert'
---@module 'busted'

local function check_heap(h)
    for i = 1, #h do
        local p = h[i]
        local l = h[i * 2]
        local r = h[i * 2 + 1]

        if l and l.val < p.val then
            return l.val, p.val
        end
        if r and r.val < p.val then
            return r.val, p.val
        end
    end
    return 1, 0
end

describe('timeout', function()
    ---@module 'fltnotify.timeout'
    local to

    before_each(function()
        to = require('fltnotify.timeout')
    end)

    after_each(function()
        to = nil
    end)

    describe('heap', function()
        local rand = math.random

        -- simple test for now ..
        local h
        before_each(function()
            h = {}
            for i = 1, 2001 do
                local n = rand(1, 40000000)
                to.timelist_push(h, { id = i, val = n })
            end
        end)
        after_each(function()
            h = nil
        end)

        it('push', function()
            local l, r = check_heap(h)
            assert.is_true(l >= r)
        end)

        it('pop', function()
            for _ = 1, 200 do
                to.timelist_pop(h)
            end
            local l, r = check_heap(h)
            assert.is_true(l >= r)
            assert.is_true(#h == (2001 - 200))
        end)

        it('replace', function()
            for i = 1, 500 do
                local n = rand(34000, 23400000)
                to.timelist_replace(h, { id = i, val = n })
            end
            local l, r = check_heap(h)
            assert.is_true(l >= r)
        end)
    end)
end)
