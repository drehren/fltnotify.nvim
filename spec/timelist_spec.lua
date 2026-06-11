---@module 'luassert'
---@module 'busted'

---@param h fltnotify.item_timeout
local function check_heap(h)
    for i = 1, #h do
        local p = h[i]
        local l = h[i * 2]
        local r = h[i * 2 + 1]

        if l and l.val > p.val then
            return l.val, p.val
        end
        if r and r.val > p.val then
            return r.val, p.val
        end
    end
    return 1, 0
end

describe('timeout', function()
    local heap = require('fltnotify.heap')
    describe('int_heap', function()
        ---@type fltnotify.simple_heap<integer>
        local h
        before_each(function()
            h = heap:new()
            local n = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }
            while #n > 0 do
                local p = math.random(#n)
                h:push(table.remove(n, p))
            end
        end)

        after_each(function()
            ---@diagnostic disable-next-line: cast-local-type
            h = nil
        end)

        it('pop', function()
            local after = {}
            while #h > 0 do
                after[#after + 1] = h:pop()
            end

            assert.same({ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }, after)
        end)
    end)

    local to = require('fltnotify.timeout')
    describe('to_heap', function()
        local rand = math.random

        -- simple test for now ..
        ---@type fltnotify.simple_heap<fltnotify.item_timeout>
        local h
        before_each(function()
            h = heap:new(function(l, r)
                return l.val < r.val
            end)
            for i = 1, 2001 do
                local n = rand(1, 40000000)
                h:push(to:new(i, n))
            end
        end)
        after_each(function()
            ---@diagnostic disable-next-line: cast-local-type
            h = nil
        end)

        it('push', function()
            local l, r = check_heap(h)
            assert.is_true(l >= r)
            assert.is_true(h:front().val <= h[1].val)
        end)

        it('pop', function()
            for _ = 1, 200 do
                assert.equal(h:front(), h:pop())
            end
            local l, r = check_heap(h)
            assert.is_true(l >= r)
            assert.is_true(#h == (2001 - 200))
            assert.is_true(h:front().val <= h[1].val)
        end)

        it('replace', function()
            for i = 1, 500 do
                local n = rand(34000, 23400000)
                h:replace(to:new(i, n))
            end
            local l, r = check_heap(h)
            assert.is_true(l >= r)
            assert.is_true(h:front().val <= h[1].val)
        end)

        it('reheap', function()
            local s = rand(6000, 7000)
            local e = rand(90000, 1000000)
            for i = e, s, -1 do
                table.remove(h, i)
            end
            h:reheap()
            local l, r = check_heap(h)
            assert.is_true(l >= r)
            assert.is_true(h:front().val <= h[1].val)
        end)
    end)
end)
