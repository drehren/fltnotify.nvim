---@module 'fltanim'

local buf_set_extmark = vim.api.nvim_buf_set_extmark
local buf_get_extmarks = vim.api.nvim_buf_get_extmarks
local buf_get_extmark_by_id = vim.api.nvim_buf_get_extmark_by_id
local buf_del_extmark = vim.api.nvim_buf_del_extmark

local mceil = math.ceil

---@alias fltnotify.progress_item integer

---@class fltnotify.item
---@field message string[]
---@field progress? fltnotify.progress_value|'cancelled'|'cancelling'
---@field timeout? fltnotify.item_timeout
---@field cancel? function
local I = {
    level = vim.log.levels.INFO,
}
I.__index = I

---@package
---@return integer width
function I:calc_width()
    return vim.iter(self.message):map(vim.fn.strwidth):fold(0, math.max)
end

---@module 'fltanim'

---@class fltnotify.manager
---@field private _cfg fltnotify.internal_config
---@field private _buf integer
---@field private _win? integer
---@field private _ns integer
---@field package _items fltnotify.item[]
---@field package _removed boolean[]
---@field package _linked table
---@field private _rlink table
---@field private _lbllen integer[]
---@field package _lblicon table<fltnotify.notification, string>
---@field package _anim fltanim.runner?
---@field package _danim string[]
---@field package _ianim {[1]: string[], [2]: number}
---@field package _aids table<fltanim.animation, fltnotify.notification>
---@field private _idas table<fltnotify.notification, fltanim.animation>
---@field private _once table<string, boolean>
---@field package _shown table<fltnotify.notification, boolean>
---@field private _totimer uv.uv_timer_t
---@field private _tolist fltnotify.item_timeout[]
---@field package _tocb function
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
---@param opts? fltnotify.notification_opts Notification content.
---@return fltnotify.notification
function M:create_notification(opts)
    vim.validate('opts', opts, 'table', true)
    local notification = #self._items + 1
    self._items[notification] = setmetatable({}, I)
    self._lbllen[notification] = 0
    if opts then
        if not opts.progress then
            opts.timeout = opts.timeout or self._cfg.timeout
        end
        self:notification_set_opts(notification, opts)
    end
    return notification
end

local function validate(lvl, ...)
    local ok, err = pcall(vim.validate, ...)
    if not ok then
        error(err, (lvl or 1) + 1)
    end
end

--- Shows a notification
---@param notification fltnotify.notification The notification to show
function M:notification_show(notification)
    local item = self:_validate_id(notification)
    if self._removed[notification] then
        return
    end

    local hide = #item.message == 0

    self:_update_buf(notification, hide)
    self:_update_win()

    local to = item.timeout
    if not hide and to then
        item.timeout = nil
        local tomgr = require('fltnotify.timeout')
        tomgr.add_timeout(self._totimer, self._tolist, to, self._tocb)
    end
end

---@private
---@param item fltnotify.item
---@param message string
function M:_set_message(item, message)
    validate(2, 'message', message, 'string')
    local msg = vim.split(message, '\r?\n')
    local change = #(item.message or '') ~= #msg
    if change then
        item.message = msg
    else
        for i = 1, #msg do
            if item.message[i] ~= msg[i] then
                item.message = msg
                change = true
                break
            end
        end
    end

    return change
end

---@private
---@param item fltnotify.item
---@param level vim.log.levels
function M:_set_level(item, level)
    validate(2, 'level', level, 'number')
    if item.level ~= level then
        item.level = level
        return true
    end
    return false
end

local pg_end = {
    done = '✓',
    cancelled = '×',
    cancelling = '⋯',
}

---@private
---@param id fltnotify.notification
---@param progress fltnotify.progress_value|'cancelled'|'cancelling'
---@return boolean
function M:_set_progress(id, progress)
    validate(2, 'progress', progress, { 'number', 'boolean', 'string' })
    local item = self._items[id]
    local changed = item.progress ~= progress
    item.progress = progress
    if progress == true then
        if self._anim then
            self:_check_progress_anim(id, item)
        else
            self._lblicon[id] = '◌'
        end
    elseif type(progress) == 'number' then
        if self._idas[id] then
            self._anim:animation_delete(self._idas[id])
            self._aids[self._idas[id]] = nil
            self._idas[id] = nil
        end
        local pv = math.max(0, math.floor(progress * (#self._danim - 1)))
        self._lblicon[id] = self._danim[pv + 1]
    else
        -- if done, we also remove the animation
        if self._idas[id] then
            self._anim:animation_delete(self._idas[id])
            self._aids[self._idas[id]] = nil
            self._idas[id] = nil
        end
        if progress then
            self._lblicon[id] = assert(
                pg_end[progress],
                "[fltnotify.set_progress] unknown value '" .. progress .. "'"
            )
            if progress ~= 'cancelling' then
                self:_set_timeout(id, self._cfg.timeout / 2)
            end
        end
    end
    return changed
end

---@param list fltnotify.item_timeout[]
---@param id fltnotify.notification
---@return boolean
local function remove_from_tolist(list, id)
    local i = 1
    local found = false
    while i <= #list do
        if list[i].id == id then
            table.remove(list, i)
            if not found then
                found = true
            end
        else
            i = i + 1
        end
    end
    return found
end

---@private
---@param id fltnotify.notification
---@param timeout number|false|nil
function M:_set_timeout(id, timeout)
    local changed = false
    if timeout == false then
        if self._shown[id] then
            local tomgr = require('fltnotify.timeout')
            if self._tolist[1] and self._tolist[1].id == id then
                tomgr.update_timelist(self._totimer, self._tolist)
                table.remove(self._tolist, 1)
                tomgr.restart_timer(self._totimer, self._tolist, self._tocb)
                changed = true
            end
        end
        return remove_from_tolist(self._tolist, id) or changed
    elseif timeout == nil then
        -- set default timeout
        ---@cast timeout -?
        timeout = self._cfg.timeout
    end
    validate(3, 'timeout', timeout, 'number')
    local ito = { id = id, val = timeout }
    if self._shown[id] then
        local tomgr = require('fltnotify.timeout')
        if self._tolist[1] and self._tolist[1].id == id then
            tomgr.update_timelist(self._totimer, self._tolist)
            changed = true
        end
        tomgr.add_timeout(self._totimer, self._tolist, ito, self._tocb)
        tomgr.restart_timer(self._totimer, self._tolist, self._tocb)
    else
        changed = not not self._items[id].timeout
            and self._items[id].timeout.val ~= ito.val
        self._items[id].timeout = ito
    end
    return changed
end

---@private
---@param item fltnotify.item
---@param cancel function|false
function M:_set_cancel(item, cancel)
    validate(2, 'cancel', cancel, { 'callable', 'boolean' })
    local changed = false
    if type(cancel) ~= 'boolean' then
        changed = item.cancel ~= cancel
        item.cancel = cancel
    else
        changed = not not item.cancel
        item.cancel = nil
    end
    return changed
end

---Sets a notification options
---@param notification fltnotify.notification
---@param opts fltnotify.notification_opts
function M:notification_set_opts(notification, opts)
    local item = self:_validate_id(notification)
    vim.validate('opts', opts, 'table')
    local changed = false
    if opts.message ~= nil then
        changed = self:_set_message(item, opts.message) or changed
    end
    if opts.level ~= nil then
        changed = self:_set_level(item, opts.level) or changed
    end
    if opts.timeout ~= nil then
        changed = self:_set_timeout(notification, opts.timeout) or changed
    end
    if opts.progress ~= nil then
        changed = self:_set_progress(notification, opts.progress) or changed
    end
    if opts.cancel ~= nil then
        changed = self:_set_cancel(item, opts.cancel) or changed
    end
    if changed and self._shown[notification] then
        self:notification_show(notification)
    end
end

--- Sets the message for the specified notification
---@param notification fltnotify.notification
---@param message string
function M:notification_set_message(notification, message)
    local item = self:_validate_id(notification)
    if self._removed[notification] then
        return
    end
    local changed = self:_set_message(item, message)
    if changed and self._shown[notification] then
        self:notification_show(notification)
    end
end

--- Sets the log level for the specified notification
---@param notification fltnotify.notification
---@param level vim.log.levels
function M:notification_set_level(notification, level)
    local item = self:_validate_id(notification)
    if self._removed[notification] then
        return
    end
    local changed = self:_set_level(item, level)
    if changed and self._shown[notification] then
        self:notification_show(notification)
    end
end

--- Sets the notification progress.
---
--- This stops the notification timeout.
---@param notification fltnotify.notification The notification
---@param progress fltnotify.progress_value Progress value, use `true` for indeterminate
function M:notification_set_progress(notification, progress)
    self:_validate_id(notification)
    if self._removed[notification] then
        return
    end
    local changed = self:_set_progress(notification, progress)
    if changed and self._shown[notification] then
        self:notification_show(notification)
    end
end

--- Sets the notification timeout.
---
--- This stops a progress notification.
---@param notification fltnotify.notification Notification id
---@param timeout number|false Timeout in milliseconds. `false` manually remove
function M:notification_set_timeout(notification, timeout)
    self:_validate_id(notification)
    if self._removed[notification] then
        return
    end
    local changed = self:_set_timeout(notification, timeout)
    if changed and self._shown[notification] then
        self:notification_show(notification)
    end
end

--- Set a notification progress cancel callback
---
--- This callback will be called by the user to cancel this progress
--- notification.
---@param notification fltnotify.notification Notification id
---@param cancel function|false Cancell callback, use `false` to remove
function M:notification_set_cancel(notification, cancel)
    local item = self:_validate_id(notification)
    if self._removed[notification] then
        return
    end
    local changed = self:_set_cancel(item, cancel)
    if changed and self._shown[notification] then
        self:notification_show(notification)
    end
end

--- Removes the notification from this manager
---@param notification fltnotify.notification Notification id
function M:notification_delete(notification)
    self:_validate_id(notification)
    self:notification_hide(notification)

    local torem = { notification }
    vim.list_extend(torem, self._linked[notification] or {})

    for _, rid in ipairs(torem) do
        if not self._removed[rid] then
            self:_set_timeout(rid, false)

            self._removed[rid] = true
            self._lblicon[rid] = nil
            if self._idas[rid] then
                self._anim:animation_delete(self._idas[rid])
                self._aids[self._idas[rid]] = nil
                self._idas[rid] = nil
            end
            local lklst = self._linked[self._rlink[rid]]
            if lklst then
                for i = 1, #lklst do
                    if lklst[i] == rid then
                        table.remove(lklst, i)
                        break
                    end
                end
            end
            self._rlink[rid] = nil

            buf_del_extmark(self._buf, self._ns, rid)
        end
    end
end

--- Checks if the notification is visible
---@param notification fltnotify.notification
---@return boolean visible
function M:notification_visible(notification)
    self:_validate_id(notification)
    return not self._removed[notification] and self._shown[notification]
end

--- Hide the specified notification
---@param notification fltnotify.notification
function M:notification_hide(notification)
    self:_validate_id(notification)
    if not self._removed[notification] then
        self:_update_buf(notification, true)

        if self._linked[notification] then
            for _, lid in ipairs(self._linked[notification]) do
                if not self._removed[lid] then
                    self:_update_buf(lid, true)
                end
            end
        end

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
        hide = false,
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

---@package
function M:_update_win()
    local height = 0
    local width = 0
    local extmarks = buf_get_extmarks(self._buf, self._ns, 0, -1, {})
    local count = 0
    for _, extm in pairs(extmarks) do
        local mw = self._lbllen[extm[1]] + self._items[extm[1]]:calc_width()
        width = math.max(width, mw)
        height = height + #self._items[extm[1]].message
        if self._rlink[extm[1]] then
            height = height + #self._items[self._rlink[extm[1]]].message
            local lmw = self._lbllen[extm[1]]
                + self._items[self._rlink[extm[1]]]:calc_width()
            width = math.max(width, lmw)
        end
        count = count + 1
    end
    local hassep = vim.fn.strwidth(self._cfg.separator) > 0
    if hassep and count > 1 then
        height = height + count - 1
    end
    if height <= 0 then
        local winconfig = { hide = true }
        vim.api.nvim_win_set_config(self._win, winconfig)
    else
        if not self._win or not vim.api.nvim_win_is_valid(self._win) then
            self:_open_win(width, height)
        else
            local winconfig = { width = width, height = height, hide = false }
            vim.api.nvim_win_set_config(self._win, winconfig)
        end
    end
end

local function set_extm_lbl(extmark, text, hl_group, ws)
    local txtw = vim.fn.strwidth(text)
    if txtw == 0 then
        return
    end
    extmark.virt_text[#extmark.virt_text + 1] = { text, hl_group }
    extmark.virt_text[#extmark.virt_text + 1] = { ' ', hl_group }
    ws[#ws + 1] = { txtw, vim.fn.strwidth(vim.trim(text)) }
end

local function add_extm_line(extmark, line, widths, sep, hl_group)
    local virt_line = {}
    for i = 1, #widths do
        local textw = widths[i][1]
        if i == #widths and sep then
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

    set_extm_lbl(extmark, label, hl_group, ws)
    if self._lblicon[id] then
        set_extm_lbl(extmark, self._lblicon[id], hl_group, ws)
    end
    if item.cancel then
        local s = '⊘' -- 󰜺 ⊗ ⊘ ⦸ ⨂
        set_extm_lbl(extmark, s, 'ErrorMsg', ws)
    end

    if #item.message > 1 then
        local smid, send = ' ', ' '
        if vim.fn.strwidth(self._cfg.separator) == 0 then
            smid, send = '│', '└'
        end
        for i = 2, #item.message - 1 do
            add_extm_line(extmark, item.message[i], ws, smid, hl_group)
        end
        add_extm_line(extmark, item.message[#item.message], ws, send, hl_group)
    end

    if self._rlink[id] then
        local lid = self._rlink[id]
        for _, m in ipairs(self._items[lid].message) do
            add_extm_line(extmark, m, ws, self._lblicon[lid] or ' ', hl_group)
        end
    end

    return extmark
end

local function get_notification_line(buf, ns_id, id)
    local ems = buf_get_extmarks(buf, ns_id, 0, -1, {})
    local last = {}
    for _, em in ipairs(ems) do
        if em[1] > id then
            break
        end
        last = em
    end
    if #last > 0 then
        if last[1] == id then
            return last[2], last[2] + 1
        else
            return last[2] + 1, last[2] + 1
        end
    end
    return 0, -1
end

local function prev_id(me, shown)
    local prev = me - 1
    while prev > 0 and not shown[prev] do
        prev = prev - 1
    end
    return prev >= 1 and prev or nil
end

local function update_virt_lines(buf, ns, id, line)
    local e = buf_get_extmark_by_id(buf, ns, id, { details = true })
    if #e > 0 then
        local em = vim.tbl_extend('keep', {}, e[3])
        em.id = id
        em.ns_id = nil
        if #line > 0 then
            if not em.virt_lines then
                em.virt_lines = {}
            end
            table.insert(em.virt_lines, { line })
        else
            table.remove(em.virt_lines)
        end
        buf_set_extmark(buf, ns, e[1], e[2], em)
    end
end

function M:_start_timeout(id, timeout)
    local tomgr = require('fltnotify.timeout')
    local to = { id = id, val = timeout }
    tomgr.add_timeout(self._totimer, self._tolist, to, self._tocb)
end

---@param id fltnotify.notification
---@param item fltnotify.item
function M:_check_progress_anim(id, item)
    if item.progress == true then
        if not self._idas[id] then
            local aid = self._anim:create_animation(unpack(self._ianim))
            self._aids[aid] = id
            self._idas[id] = aid
        elseif self._anim:animation_is_paused(self._idas[id]) then
            self._anim:animation_unpause(self._idas[id])
        end
        if not self._anim:is_running() then
            self._anim:restart()
        end
    end
end

---@package
---@param id fltnotify.notification
---@param hide boolean
function M:_update_buf(id, hide)
    if self._linked[id] then
        self._shown[id] = not hide
        for _, aid in ipairs(self._linked[id]) do
            self:_update_buf(aid, hide)
        end
        return
    end
    local item = self:_validate_id(id)
    local sepw = vim.fn.strwidth(self._cfg.separator)
    if not hide then
        local label = self._cfg.level[item.level].label
        local hl_group = self._cfg.level[item.level].hl_group
        local lstart, lend = get_notification_line(self._buf, self._ns, id)
        local extm = self:_prepare_extmark(id, item, label, hl_group)
        self._lbllen[id] = vim.iter(extm.virt_text):fold(0, function(n, chunk)
            return n + vim.fn.strwidth(chunk[1])
        end)

        if sepw > 0 then
            if lstart > 0 and lstart >= lend then
                local prev = prev_id(id, self._shown)
                update_virt_lines(self._buf, self._ns, prev, {
                    self._cfg.separator:rep(mceil(vim.o.columns / sepw)),
                })
            elseif lstart < vim.api.nvim_buf_line_count(self._buf) - 1 then
                local tmp = self._cfg.separator:rep(mceil(vim.o.columns / sepw))
                table.insert(extm.virt_lines, { { tmp } })
            end
        end

        vim.api.nvim_buf_set_lines(self._buf, lstart, lend, true, {
            item.message[1],
        })
        buf_set_extmark(self._buf, self._ns, lstart, 0, extm)
    else
        local em = buf_get_extmark_by_id(self._buf, self._ns, id, {})
        if #em == 0 then
            return
        end
        if
            sepw > 0
            and em[1] > 0
            and vim.api.nvim_buf_line_count(self._buf) == em[1]
        then
            local prev = prev_id(id, self._shown)
            update_virt_lines(self._buf, self._ns, prev, {})
        end
        vim.api.nvim_buf_set_lines(self._buf, em[1], em[1] + 1, true, {})
    end
    self._shown[id] = not hide
end

--- Creates and sends a new notification
---@param msg string Content of the notification to show to the user
---@param level? vim.log.levels One of the values from `vim.log.levels`
---@param opts? fltnotify.notification_opts Additional notification data
function M:notify(msg, level, opts)
    vim.validate('msg', msg, 'string')
    vim.validate('level', level, 'number', true)
    vim.validate('opts', opts, 'table', true)

    opts = opts or {}
    opts.level = level or opts.level
    opts.timeout = opts.timeout or self._cfg.timeout

    local nopts = vim.tbl_extend('force', { message = msg }, opts)
    local id = self:create_notification(nopts)
    self:notification_show(id)
end

--- Creates and sends a new notification, shown only the first time
---@param msg string Content of the notification to show to the user
---@param level? vim.log.levels One of the values from `vim.log.levels`
---@param opts? fltnotify.notification_opts Additional notification data
function M:notify_once(msg, level, opts)
    vim.validate('msg', msg, 'string')
    vim.validate('level', level, 'number', true)
    vim.validate('data', opts, 'table', true)

    if not self._once[msg] then
        self._once[msg] = true
        self:notify(msg, level, opts)
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
        marks[#marks + 1] = mark
        line = endline
    end

    vim.api.nvim_set_option_value('ma', true, { buf = buf })
    vim.api.nvim_buf_set_lines(buf, 0, -1, true, text)
    vim.api.nvim_set_option_value('ma', false, { buf = buf })

    for _, mark in ipairs(marks) do
        buf_set_extmark(buf, self._ns, mark[1], 0, {
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

    if self._cancel_cmd then
        vim.api.nvim_del_user_command(self._cancel_cmd)
    end
end

---@private
---@param id fltnotify.notification
function M:_cancel_progress(id)
    local idn = self._items[id].cancel()
    if idn then
        local ok = pcall(M._validate_id, self, idn)
        if ok then
            if not self._linked[idn] then
                self._linked[idn] = {}
            end
            table.insert(self._linked[idn], id)
            self._rlink[id] = idn
        end
        self:_set_progress(id, 'cancelling')
        self:_set_timeout(id, false)
        self:_set_timeout(idn, false)
    else
        self:_set_progress(id, 'cancelled')
    end
    self:_set_cancel(self._items[id], false)
    self:notification_show(idn or id)
    done = true
end

--- Cancel ongoing progress notification if cancellable.
---@param notification fltnotify.notification
function M:notification_progress_cancel(notification)
    local item = self:_validate_id(notification)
    if self._removed[notification] then
        return
    end
    local ok = pcall(
        vim.validate,
        'notification.progress',
        item.progress,
        { 'number', 'boolean' }
    )
    if not ok then
        -- notification progress is ending or has ended already
        return
    end
    if not item.cancel then
        error('[fltnotify] notification is not cancellable')
    end

    self:_cancel_progress(notification)
end

--- Creates a user command to cancel progress notifications sent to this manager
---@param name string
function M:create_cancelation_command(name)
    vim.validate('name', name, 'string')

    if self._cancel_cmd and self._cancel_cmd ~= name then
        vim.api.nvim_del_user_command(self._cancel_cmd)
    end
    self._cancel_cmd = name

    -- prepare cancellable
    local function cancel(cmd)
        local tocancel = {}
        for i = 1, #cmd.fargs do
            cmd.fargs[i] = cmd.fargs[i]:gsub('\\ ', ' ')
            local arg = cmd.fargs[i]
            for id, item in ipairs(self._items) do
                if
                    not self._removed[id]
                    and item.cancel
                    and (cmd.bang or arg == item.message[1])
                then
                    tocancel[#tocancel + 1] = id
                    break
                end
            end
        end
        for _, id in ipairs(tocancel) do
            self:_cancel_progress(id)
        end
        if #tocancel == 0 and #cmd.fargs > 0 then
            vim.api.nvim_echo({
                { 'Notifications "' },
                { table.concat(cmd.fargs, '", "') },
                { '" not found' },
            }, true, { err = true })
        end
    end
    vim.api.nvim_create_user_command(name, cancel, {
        bang = true,
        nargs = '*',
        desc = 'Cancels progress notification',
        complete = function(lead, cmdline)
            local current = {}
            for id, item in ipairs(self._items) do
                if
                    not self._removed[id]
                    and item.cancel
                    and not cmdline:find(item.message[1])
                then
                    current[#current + 1] = vim.fn.escape(item.message[1], ' ')
                end
            end
            return vim.tbl_filter(function(v)
                return vim.startswith(v, lead)
            end, current)
        end,
    })
end

return {
    ---Creates a new notification manager
    ---@param config fltnotify.config
    ---@return fltnotify.manager
    new = function(config)
        local cfg = require('fltnotify.config').get(config)
        ---@type fltnotify.manager
        local mgr
        mgr = {
            _cfg = cfg,
            _items = {},
            _ns = vim.api.nvim_create_namespace(''),
            _buf = vim.api.nvim_create_buf(false, true),
            _removed = {},
            _shown = {},
            _once = {},
            _lbllen = {},
            _lblicon = {},
            _idas = {},
            _aids = {},
            _ianim = {},
            _danim = {},
            _totimer = assert(vim.uv.new_timer()),
            _tolist = {},
            _tocb = vim.schedule_wrap(function(notification)
                mgr:notification_delete(notification)
            end),
            _linked = {},
            _rlink = {},
        }
        ---@cast mgr fltnotify.manager
        local ok, anim = pcall(require, 'fltanim')
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
            mgr._anim = anim.new(
                cfg.progress_animation.fps,
                vim.schedule_wrap(function(items)
                    for _, item in ipairs(items) do
                        local id = mgr._aids[item.id]
                        if id and mgr._shown[id] and not mgr._removed[id] then
                            mgr._lblicon[id] = item.frame
                            mgr:_update_buf(id, #mgr._items[id].message == 0)
                        end
                    end
                    mgr:_update_win()
                end)
            )
        else
            for i = 0, 1000 do
                mgr._danim[i] = ('%3.1f%%'):format(i / 10)
            end
        end
        return setmetatable(mgr, M)
    end,
}
