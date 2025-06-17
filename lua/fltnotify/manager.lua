---@module 'fltanim'

---@alias fltnotify.progress_item integer

---@class fltnotify.item
---@field lastwidth? integer
---@field message string[]
---@field progress? fltnotify.progress_value
---@field timeout? number|false
local I = {
    level = vim.log.levels.INFO,
}
I.__index = I

---@package
---@return integer width
function I:calc_width()
    return vim.iter(self.message):map(vim.fn.strwidth):fold(0, math.max)
end

---@class fltnotify.item_timeout
---@field id fltnotify.notification
---@field val number

---@param heap fltnotify.item_timeout[]
---@param value fltnotify.item_timeout
local function heap_push(heap, value)
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
local function heap_replace(heap, value)
    assert(#heap > 0, 'list is empty')
    local val = heap[1]
    heap[1] = value
    local idx = 1
    local lidx = 2
    local ridx = 3
    while heap[idx] do
        if heap[lidx] and heap[idx].val > heap[lidx].val then
            heap[idx], heap[lidx] = heap[lidx], heap[idx]
            idx = 2 * lidx
        elseif heap[ridx] and heap[idx].val > heap[ridx].val then
            heap[idx], heap[ridx] = heap[ridx], heap[idx]
            idx = 2 * ridx
        else
            break
        end
        lidx = idx + 1
        ridx = idx + 2
    end
    return val
end

---@param heap fltnotify.item_timeout[]
---@return fltnotify.item_timeout
local function heap_pop(heap)
    if #heap == 1 then
        return table.remove(heap)
    end
    return heap_replace(heap, table.remove(heap))
end

---@param timer uv.uv_timer_t
---@param timelist fltnotify.item_timeout[]
---@return fltnotify.item_timeout?
local function update_timelist(timer, timelist)
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
local function restart_timer(timer, timelist, callback)
    if not tmcache[callback] then
        local function timedone()
            local popedids = {}
            local t = heap_pop(timelist)
            callback(t.id)
            popedids[t.id] = true
            for _, v in ipairs(timelist) do
                v.val = v.val - t.val
            end
            while #timelist > 0 and timelist[1].val <= 0 do
                t = heap_pop(timelist)
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
local function add_timeout(timer, timelist, timeout, callback)
    local cur = update_timelist(timer, timelist)
    heap_push(timelist, timeout)
    if cur and cur.val == timelist[1].val then
        return
    end
    if timer:is_active() then
        timer:stop()
    end
    restart_timer(timer, timelist, callback)
end

---@module 'fltanim'

---@class fltnotify.manager
---@field private _cfg fltnotify.internal_config
---@field private _buf integer
---@field private _ns integer
---@field private _items fltnotify.item[]
---@field private _removed boolean[]
---@field private _lbllen integer[]
---@field private _pframe fltnotify.progress_item[]
---@field private _anim fltanim.runner?
---@field private _danim string[]
---@field private _aids table<fltanim.animation, fltnotify.notification>
---@field private _idas table<fltnotify.notification, fltanim.animation>
---@field private _once table<string, boolean>
---@field private _shown table<fltnotify.notification, boolean>
---@field private _win? integer
---@field private _totimer uv.uv_timer_t
---@field private _tolist fltnotify.item_timeout[]
---@field private _toutcb function
---@field private _icon table<fltnotify.notification, string>
---@field private _ianim table
local M = {}
M.__index = M

---@private
function M:_validate_id(id)
    if not self._items[id] then
        local callee = debug.getinfo(2, 'n').name
        local msg = ('%s: expected a notification id, got %s'):format(
            callee,
            id or 'nil'
        )
        error(msg, 2)
    end
    return self._items[id]
end

--- Gets the currently defined timeout
---@return number
function M:timeout()
    return self._cfg.timeout
end

--- Creates a new notification.
---
--- The new notification will timeout based on this manager configuration.
--- If you don't want this, use [notification_set_timeout](lua://fltanim.manager:notification_set_timeout) with `false`.
---@return fltnotify.notification
function M:create_notification()
    self._items[#self._items + 1] = setmetatable({}, I)
    self._lbllen[#self._lbllen + 1] = 0
    return #self._items
end

---@class fltnotify.notification_other_data
---@field progress? number|true
---@field timeout? number

--- Shows a notification
---@param notification fltnotify.notification The notification to show
---@param msg? string Set or change the notification message
---@param other_data? fltnotify.notification_other_data Set or change other notification data
function M:notification_show(notification, msg, other_data)
    local item = self:_validate_id(notification)
    if self._removed[notification] then
        return
    end
    other_data = other_data or {}

    -- avoid recursion
    self._shown[notification] = false

    if msg then
        self:notification_set_message(notification, msg)
    end
    if other_data.progress then
        self:notification_set_progress(notification, other_data.progress)
    end
    if other_data.timeout then
        self:notification_set_timeout(notification, other_data.timeout)
    end

    local hide = #item.message == 0

    if not hide and item.progress == true then
        if not self._anim then
            self._icon[notification] = '◌'
        else
            if not self._idas[notification] then
                local aid = self._anim:create_animation(unpack(self._ianim))
                self._aids[aid] = notification
                self._idas[notification] = aid
            elseif self._anim:animation_is_paused(self._idas[notification]) then
                self._anim:animation_unpause(self._idas[notification])
            end
        end
    end

    self:_update_buf(notification, hide)
    self:_update_win()

    self._shown[notification] = true

    if not hide and item.timeout then
        local timeout = self:_resolve_timeout(notification)
        if #self._tolist > 0 and self._tolist[1].id == notification then
            update_timelist(self._totimer, self._tolist)
            heap_replace(self._tolist, { id = notification, val = timeout })
            restart_timer(self._totimer, self._tolist, self._toutcb)
        end
        add_timeout(
            self._totimer,
            self._tolist,
            { id = notification, val = timeout },
            self._toutcb
        )
    end
end

--- Sets the message for the specified notification
---@param notification fltnotify.notification
---@param message string
function M:notification_set_message(notification, message)
    local item = self:_validate_id(notification)
    vim.validate('message', message, 'string')
    if not self._removed[notification] then
        item.message = vim.split(message, '\r?\n')
        if self._shown[notification] then
            self:notification_show(notification)
        end
    end
end

--- Sets the log level for the specified notification
---@param notification fltnotify.notification
---@param level vim.log.levels
function M:notification_set_level(notification, level)
    local item = self:_validate_id(notification)
    vim.validate('level', level, 'number')
    if not self._removed[notification] then
        item.level = level
        if self._shown[notification] then
            self:notification_show(notification)
        end
    end
end

--- Sets the notification progress.
---
--- This stops the notification timeout.
---@param notification fltnotify.notification The notification
---@param progress fltnotify.progress_value Progress value, use `true` for indeterminate
function M:notification_set_progress(notification, progress)
    self:_validate_id(notification)
    vim.validate('progress', progress, { 'number', 'boolean', 'string' })
    if not self._removed[notification] then
        self:_set_progress(notification, progress)
        if self._shown[notification] then
            self:notification_show(notification)
        end
    end
end

--- Sets the notification timeout.
---
--- This stops a progress notification.
---@param notification fltnotify.notification Notification id
---@param timeout number|false Timeout in milliseconds. `false` manually remove
function M:notification_set_timeout(notification, timeout)
    self:_validate_id(notification)
    if not self._removed[notification] then
        self:_set_timeout(notification, timeout)
        if self._shown[notification] then
            self:notification_show(notification)
        end
    end
end

---@private
---@param id fltnotify.notification
---@param progress fltnotify.progress_value
function M:_set_progress(id, progress)
    local item = self._items[id]
    item.progress = progress
    if progress and progress ~= true and progress ~= 'done' then
        if self._idas[id] and self._anim then
            self._anim:animation_delete(self._idas[id])
            self._idas[id] = nil
        end
        local pv = math.max(0, math.floor(progress * (#self._danim - 1)))
        self._icon[id] = self._danim[pv + 1]
    else
        -- if done, we also remove the animation
        if self._idas[id] and self._anim then
            self._anim:animation_delete(self._idas[id])
            self._idas[id] = nil
        end
        if progress == 'done' then
            self._icon[id] = '✓'
        else
            self._icon[id] = nil
        end
    end
end

local function uniquify_heap(table, id)
    local i = 2
    while i <= #table do
        if table[i].id == id then
            table.remove(i)
        else
            i = i + 1
        end
    end
end

---@private
---@param id fltnotify.notification
---@param timeout number|false
function M:_set_timeout(id, timeout)
    local item = self._items[id]
    if #self._tolist > 0 and self._tolist[1].id == id then
        update_timelist(self._totimer, self._tolist)
        heap_pop(self._tolist)
        restart_timer(self._totimer, self._tolist, self._toutcb)
    end
    item.timeout = timeout
end

--- Removes the notification from this manager
---@param notification fltnotify.notification Notification id
function M:notification_delete(notification)
    self:_validate_id(notification)
    self:notification_hide(notification)

    self._removed[notification] = true
    self._icon[notification] = nil
    if self._idas[notification] and self._anim then
        self._anim:animation_delete(self._idas[notification])
        self._aids[self._idas[notification]] = nil
        self._idas[notification] = nil
    end
    self._pframe[notification] = nil
    if #self._tolist > 0 and self._tolist[1].id == notification then
        update_timelist(self._totimer, self._tolist)
        heap_pop(self._tolist)
        restart_timer(self._totimer, self._tolist, self._toutcb)
    end
    uniquify_heap(self._tolist, notification)
    vim.api.nvim_buf_del_extmark(self._buf, self._ns, notification)
end

--- Checks if the notification is visible
---@param notification fltnotify.notification
---@return boolean visible
function M:visible(notification)
    self:_validate_id(notification)
    if self._removed[notification] then
        return false
    end
    local em = vim.api.nvim_buf_get_extmark_by_id(
        self._buf,
        self._ns,
        notification,
        {}
    )
    return #em > 0
end

--- Hide the specified notification
---@param notification fltnotify.notification
function M:notification_hide(notification)
    self:_validate_id(notification)
    if not self._removed[notification] then
        self:_update_buf(notification, true)
        self:_update_win()
    end
end

--- Open the notification winow
---@private
---@param width number
---@param height number
function M:_open_win(width, height)
    ---@type vim.api.keyset.win_config
    local winconfig = {
        relative = 'editor',
        border = self._cfg.border,
        anchor = self._cfg.anchor,
        focusable = false,
        mouse = false,
        noautocmd = true,
        style = 'minimal',
        width = width,
        height = height,
        title = self._cfg.title,
        title_pos = self._cfg.title and self._cfg.title_pos or nil,
        zindex = 1000,
    }
    if vim.startswith(winconfig.anchor, 'N') then
        winconfig.row = self._cfg.margin[1]
    else
        winconfig.row = vim.o.lines - vim.o.cmdheight - self._cfg.margin[1]
    end
    if vim.endswith(winconfig.anchor, 'W') then
        winconfig.col = self._cfg.margin[2]
    else
        winconfig.col = vim.o.columns - self._cfg.margin[2]
    end
    self._win = vim.api.nvim_open_win(self._buf, false, winconfig)
end

---@private
function M:_update_win()
    local height = 0
    local width = 0
    local extmarks = vim.api.nvim_buf_get_extmarks(self._buf, self._ns, 0, -1, {
        details = true,
    })
    local hassep = vim.fn.strwidth(self._cfg.separator) > 0
    for _, extm in pairs(extmarks) do
        if #extm > 0 then
            local mw = self._lbllen[extm[1]] + self._items[extm[1]]:calc_width()
            self._items[extm[1]].lastwidth = mw
            width = math.max(width, mw, self._items[extm[1]].lastwidth)
            height = height + #self._items[extm[1]].message
            if extm[2] > 0 and hassep then
                height = height + 1
            end
        end
    end
    if height == 0 then
        if self._win and vim.api.nvim_win_is_valid(self._win) then
            vim.api.nvim_win_close(self._win, true)
            self._win = nil
        end
    else
        if not self._win or not vim.api.nvim_win_is_valid(self._win) then
            self:_open_win(width, height)
        else
            local winconfig = { width = width, height = height }
            vim.api.nvim_win_set_config(self._win, winconfig)
        end
    end
end

-- creo q la solucion en si esta bien.. pero igual quiero hacer "poco"..
-- para eso debiera cachar cual fue el cambio..
-- entonces una notificacion seria:
--
-- [<dyn_icon> ][<label>     ]notification line 1
-- [<no_sep_msg_indicator    ]notification line 2
-- [<no_sep_end_msg_indicator]notification line n

local function set_extm_lbl(extmark, text, hl_group)
    extmark.virt_text[#extmark.virt_text + 1] = { text, hl_group }
    extmark.virt_text[#extmark.virt_text + 1] = { ' ', hl_group }
end

local function add_extm_line(extmark, line, widths, sep, hl_group)
    local virt_line = {}
    for i = 1, #widths do
        local textw = widths[i][1]
        if sep then
            local mid = math.floor((textw - widths[i][2]) / 2)
            virt_line[#virt_line + 1] = { (' '):rep(mid), hl_group }
            virt_line[#virt_line + 1] = { sep, hl_group }
            textw = textw - mid - 1
        end
        virt_line[#virt_line + 1] = { (' '):rep(textw), hl_group }
        virt_line[#virt_line + 1] = { ' ', hl_group }
    end
    virt_line[#virt_line + 1] = { line, hl_group }
    extmark.virt_lines[#extmark.virt_lines + 1] = virt_line
end

---@param id integer
---@param item fltnotify.item
---@param label string
---@param hl_group number|string
---@return vim.api.keyset.set_extmark
function M:_prepare_extmark(id, item, label, hl_group)
    ---@type vim.api.keyset.set_extmark
    local extmark = {
        id = id,
        virt_text = {},
        virt_text_pos = 'inline',
        end_col = vim.fn.strwidth(item.message[1]),
        undo_restore = false,
        invalidate = true,
        virt_lines = {},
        hl_group = hl_group,
        hl_eol = true,
    }
    local ws = {}
    if self._icon[id] then
        local iconw = vim.fn.strwidth(self._icon[id])
        if iconw > 0 then
            set_extm_lbl(extmark, self._icon[id], hl_group)
            ws[#ws + 1] = { iconw, vim.fn.strwidth(vim.trim(self._icon[id])) }
        end
    end
    local lblw = vim.fn.strwidth(label)
    if lblw > 0 then
        set_extm_lbl(extmark, label, hl_group)
        ws[#ws + 1] = { lblw, vim.fn.strwidth(vim.trim(label)) }
    end
    local smid, send = ' ', ' '
    if #item.message > 1 then
        if vim.fn.strwidth(self._cfg.separator) > 0 then
            smid, send = '│', '└'
        end
        for i = 2, #item.message - 1 do
            add_extm_line(extmark, item.message[i], ws, smid, hl_group)
        end
        add_extm_line(extmark, item.message[#item.message], ws, send, hl_group)
    end

    return extmark
end

---@private
---@return string
-- function M:_make_label(id)
--     local item = self._items[id]
--     local cfglvl = self._cfg.level[item.level]
--     if not item.progress then
--         return cfglvl.label
--     elseif item.progress == true then
--         return ' ' -- handled by animator
--     elseif item.progress ~= 'done' then
--         return self._danim[self._pframe[id]]
--     else
--         return '✓'
--     end
-- end

local function get_notification_line(buf, ns_id, id)
    local ems = vim.api.nvim_buf_get_extmarks(buf, ns_id, 0, -1, {})
    local last = {}
    for _, em in ipairs(ems) do
        if em[1] > id then
            break
        end
        last = em
    end
    if #last > 0 then
        if last[1] == id then
            return last[2], true
        else
            return last[2] + 1, false
        end
    end
    return 0, false
end

---@private
---@param id fltnotify.notification
---@param hide boolean
function M:_update_buf(id, hide)
    local item = self:_validate_id(id)
    if not hide then
        local label = self._cfg.level[item.level].label
        local hl_group = self._cfg.level[item.level].hl_group
        local line, replace = get_notification_line(self._buf, self._ns, id)
        local extm = self:_prepare_extmark(id, item, label, hl_group)
        self._lbllen[id] = vim.iter(extm.virt_text):fold(0, function(n, chunk)
            return n + vim.fn.strwidth(chunk[1])
        end)
        if not replace then
            print('showing', id, 'at line', line)
        end

        local sepw = vim.fn.strwidth(self._cfg.separator)
        if sepw > 0 and line > 0 then
            vim.print(sepw, self._cfg.separator)
            if not replace then
                vim.api.nvim_buf_set_lines(self._buf, line, line, true, {
                    self._cfg.separator:rep(math.ceil(vim.o.columns / sepw)),
                })
            end
            line = line + 1
        end

        extm.end_row = line
        vim.api.nvim_buf_set_lines(
            self._buf,
            line,
            line + (replace and 1 or 0),
            true,
            { item.message[1] }
        )
        pcall(vim.api.nvim_buf_set_extmark, self._buf, self._ns, line, 0, extm)
    else
        local em =
            vim.api.nvim_buf_get_extmark_by_id(self._buf, self._ns, id, {})
        if #em == 0 then
            return
        end
        print('hidding', id, 'at line', em[1])
        vim.api.nvim_buf_set_lines(self._buf, em[1], em[1] + 1, true, {})
    end
end

---@private
---@param notification fltnotify.notification
---@return number timeout
function M:_resolve_timeout(notification)
    local item = self._items[notification]
    if not item.timeout or item.timeout == true then
        return self._cfg.timeout
    else
        ---@diagnostic disable-next-line: return-type-mismatch
        return item.timeout
    end
end

--- Creates and sends a new notification
---@param msg string Content of the notification to show to the user
---@param level vim.log.levels One of the values from `vim.log.levels`
---@param other_data fltnotify.notification_data Additional notification data
function M:notify(msg, level, other_data)
    vim.validate('msg', msg, 'string')
    vim.validate('level', level, 'number', true)
    other_data = other_data or {}

    local notification = self:create_notification()
    self:notification_set_message(notification, msg)
    if level then
        self:notification_set_level(notification, level)
    end
    if other_data.timeout then
        self:notification_set_timeout(notification, other_data.timeout)
    end
    if other_data.progress then
        self:notification_set_progress(notification, other_data.progress)
    end
    if other_data.level then
        self:notification_set_level(notification, other_data.level)
    end

    local timeout = self:_resolve_timeout(notification)
    self._items[notification].timeout = nil

    self:notification_show(notification)
    vim.defer_fn(function()
        self:notification_delete(notification)
    end, timeout)
end

--- Creates and sends a new notification, shown only the first time
---@param msg string Content of the notification to show to the user
---@param level vim.log.levels One of the values from `vim.log.levels`
---@param data fltnotify.notification_data Additional notification data
function M:notify_once(msg, level, data)
    vim.validate('msg', msg, 'string')
    vim.validate('level', level, 'number', true)
    vim.validate('data', data, 'table', true)

    if not self._once[msg] then
        self._once[msg] = true
        self:notify(msg, level, data)
    end
end

--- Creates a buffer containing all notification messages sent to this notification manager
---@param ns string Log name
---@return integer buffer
function M:create_notifications_log(ns)
    local name = ('fltnotify://%s.log'):format(ns)
    local buf = vim.fn.bufnr(name)
    if buf == -1 then
        buf = vim.api.nvim_create_buf(true, true)
        vim.api.nvim_buf_set_name(buf, name)
        vim.api.nvim_set_option_value('bt', 'nofile', { buf = buf })
    end

    local text = {}
    local marks = {}
    local line = 0
    for i, item in ipairs(self._items) do
        local endline = line + #item.message
        if i > 1 then
            text[#text + 1] = '' -- separate notifications
            line = line + 1
            endline = endline + 1
        end
        vim.list_extend(text, item.message)
        local mark = {
            line,
            endline + 1,
            self._cfg.level[item.level].hl_group,
        }
        print('item', i, vim.inspect(mark))
        marks[#marks + 1] = mark
        line = endline
    end

    vim.api.nvim_set_option_value('ma', true, { buf = buf })
    vim.api.nvim_buf_set_lines(buf, 0, -1, true, text)
    vim.api.nvim_set_option_value('ma', false, { buf = buf })

    for _, mark in ipairs(marks) do
        vim.api.nvim_buf_set_extmark(buf, self._ns, mark[1], 0, {
            end_col = 0,
            end_row = mark[2] - 1,
            hl_group = mark[3],
        })
    end

    vim.api.nvim_buf_set_keymap(buf, 'n', 'q', '<cmd>close<cr>', {
        nowait = true,
        silent = true,
    })

    return buf
end

--- Call this function when removing the notification manager
function M:destroy()
    if self._anim then
        self._anim:stop()
    end
    self._totimer:stop()
    vim.api.nvim_buf_delete(self._buf, { unload = true })
end

return {
    new = function(config)
        local cfg = require('fltnotify.config').get(config)
        local mgr
        mgr = {
            _cfg = cfg,
            _items = {},
            _ns = vim.api.nvim_create_namespace(''),
            _buf = vim.api.nvim_create_buf(false, true),
            _removed = {},
            _pframe = {},
            _once = {},
            _lbllen = {},
            _aids = {},
            _totimer = vim.uv.new_timer(),
            _tolist = {},
            _idas = {},
            _shown = {},
            _icon = {},
            _ianim = {},
            _changes = 0,
        }
        local ok, anim = pcall(require, 'fltanim')
        ok = false
        if ok then
            local animations = require('fltanim.animations')
            mgr._danim = animations[cfg.progress_animation.determinate](
                cfg.progress_animation.width
            )
            mgr._ianim = {
                animations[cfg.progress_animation.indeterminate](
                    cfg.progress_animation.width
                ),
            }
            mgr._anim = anim.new(cfg.progress_animation.fps, function(items)
                for _, item in ipairs(items) do
                    local id = mgr._idas[item.id]
                    if not mgr._removed[id] then
                        mgr._icon[id] = item.frame
                        mgr:_update_buf(id, #mgr._items[id].message > 0)
                    end
                end
                mgr:_update_win()
            end)
        else
            mgr._danim = {}
            for i = 0, 1000 do
                mgr._danim[i] = ('%3.1f%%'):format(i / 10)
            end
        end
        mgr._toutcb = vim.schedule_wrap(function(notification)
            mgr:notification_hide(notification)
        end)
        return setmetatable(mgr, M)
    end,
}
