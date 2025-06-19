local to = require('fltnotify.timeout')

-- simple test for now ..
local h = {}
for i = 1, 2000 do
    local n = math.random(1, 40000000)
    to.timelist_push(h, { id = i, val = n })
end
local function test(what)
    for p = 1, math.floor(math.log(#h, 2) * 2 + 1) do
        local l = p * 2
        local r = l + 1
        assert(
            h[l] and h[p].val <= h[l].val and h[r] and h[p].val <= h[r].val,
            ('bad %s found at p:%d,%d; l:%d,%d; r:%d,%d'):format(
                what,
                p,
                h[p].val,
                l,
                h[l].val,
                r,
                h[r].val
            )
        )
    end
end
test('push')

for _ = 1, 200 do
    to.timelist_pop(h)
end
test('pop')
assert(#h == (2000 - 200), 'bad pop!')

for i = 1, 500 do
    local n = math.random(34000, 23400000)
    to.timelist_replace(h, { id = i, val = n })
end
test('replace')
