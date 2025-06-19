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

---@module 'fltanim'

---@class fltnotify.manager
---@field private _cfg fltnotify.internal_config
---@field private _buf integer
---@field private _win? integer
---@field private _ns integer
---@field package _items fltnotify.item[]
---@field package _removed boolean[]
---@field private _lbllen integer[]
---@field package _lblicon table<fltnotify.notification, string>
---@field package _anim fltanim.runner?
---@field package _danim string[]
---@field package _ianim {[1]: string[], [2]: number}
---@field package _aids table<fltanim.animation, fltnotify.notification>
---@field private _idas table<fltnotify.notification, fltanim.animation>
---@field private _once table<string, boolean>
---@field private _shown table<fltnotify.notification, boolean>
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
    self._items[#self._items + 1] = setmetatable({}, I)
    self._lbllen[#self._lbllen + 1] = 0
    local notification = #self._items
    if opts then
        self:_set_opts(
            2,
            notification,
            opts.message,
            opts.timeout or self._cfg.timeout,
            opts.level,
            opts.progress
        )
    end
    return #self._items
end

local function _validate(lvl, ...)
    local ok, err = pcall(vim.validate, ...)
    if not ok then
        error(err, (lvl or 1) + 1)
    end
end

---@private
---@param l integer error level
---@param id fltnotify.notification
---@param msg string?
---@param to (number|false)?
---@param level vim.log.levels?
---@param pg fltnotify.progress_value?
---@return number|false
function M:_set_opts(l, id, msg, to, level, pg)
    if l > 0 then
        _validate(l, 'message', msg, 'string', true)
        _validate(l, 'timeout', to, { 'number', 'boolean' }, true)
        _validate(l, 'level', level, 'number', true)
        _validate(l, 'progress', pg, { 'number', 'string', 'boolean' }, true)
    end
    local item = self._items[id]
    local updbits = 0
    if msg ~= nil then
        item.message = vim.split(msg, '\r?\n')
        updbits = updbits + 1
    end
    if to ~= nil and to ~= item.timeout then
        self:_set_timeout(id, to)
        updbits = updbits + 2
    end
    if level ~= nil and item.level ~= level then
        item.level = level
        updbits = updbits + 4
    end
    if pg ~= nil and item.progress ~= pg then
        self:_set_progress(id, pg)
        updbits = updbits + 8
    end
    return updbits > 0 and updbits or false
end

--- Shows a notification
---@param notification fltnotify.notification The notification to show
---@param msg? string Set or change the notification message
---@param opts? fltnotify.notification_opts Set or change other notification data
function M:notification_show(notification, msg, opts)
    local item = self:_validate_id(notification)
    if self._removed[notification] then
        return
    end

    local progrupd = false
    local toupd = not self._shown[notification]
    if opts then
        opts.message = msg or opts.message
        local upd = self:_set_opts(
            2,
            notification,
            opts.message,
            opts.timeout,
            opts.level,
            opts.progress
        )
        if upd then
            toupd = bit.band(upd, 2) == 2 or toupd
            progrupd = bit.band(upd, 8) == 8
        elseif self._shown[notification] then
            return
        end
    end

    local hide = #item.message == 0

    if not hide and progrupd and item.progress == true then
        if self._anim then
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
    self._shown[notification] = not hide

    self:_update_win()

    if not hide and toupd and item.timeout then
        local to = require('fltnotify.timeout')
        to.add_timeout(
            self._totimer,
            self._tolist,
            { id = notification, val = item.timeout },
            self._tocb
        )
    end
end

---Sets a notification options
---@param notification fltnotify.notification
---@param opts fltnotify.notification_opts
function M:notification_set_opts(notification, opts)
    self:_validate_id(notification)
    vim.validate('opts', opts, 'table')
    if not self._removed[notification] then
        local changed = self:_set_opts(
            2,
            notification,
            opts.message,
            opts.timeout,
            opts.level,
            opts.progress
        )
        if changed and self._shown[notification] then
            self:notification_show(notification)
        end
    end
end

--- Sets the message for the specified notification
---@param notification fltnotify.notification
---@param message string
function M:notification_set_message(notification, message)
    self:_validate_id(notification)
    vim.validate('message', message, 'string')
    if not self._removed[notification] then
        local changed = self:_set_opts(0, notification, message)
        if changed and self._shown[notification] then
            self:notification_show(notification)
        end
    end
end

--- Sets the log level for the specified notification
---@param notification fltnotify.notification
---@param level vim.log.levels
function M:notification_set_level(notification, level)
    self:_validate_id(notification)
    vim.validate('level', level, 'number')
    if not self._removed[notification] then
        local changed = self:_set_opts(0, notification, nil, nil, level)
        if changed and self._shown[notification] then
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
        local changed = self:_set_opts(0, notification, nil, nil, nil, progress)
        if changed and self._shown[notification] then
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
        local changed = self:_set_opts(2, notification, nil, timeout)
        if changed and self._shown[notification] then
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
    if progress == true then
        if not self._anim then
            self._lblicon[id] = '◌'
        end
    elseif type(progress) == 'number' then
        if self._idas[id] then
            self._anim:animation_delete(self._idas[id])
            self._idas[id] = nil
        end
        local pv = math.max(0, math.floor(progress * (#self._danim - 1)))
        self._lblicon[id] = self._danim[pv + 1]
    else
        -- if done, we also remove the animation
        if self._idas[id] then
            self._anim:animation_delete(self._idas[id])
            self._idas[id] = nil
        end
        if progress == 'done' then
            self._lblicon[id] = '✓'
        else
            self._lblicon[id] = nil
        end
    end
end

local function remove_from_list(list, id)
    local i = 1
    while i <= #list do
        if list[i].id == id then
            table.remove(list, i)
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
    item.timeout = timeout
    if self._shown[id] then
        if type(item.timeout) == 'number' then
            local to = require('fltnotify.timeout')
            to.add_timeout(
                self._totimer,
                self._tolist,
                { id = id, val = item.timeout },
                self._tocb
            )
        else
            if self._tolist[1] and self._tolist[1].id == id then
                local to = require('fltnotify.timeout')
                to.update_timelist(self._totimer, self._tolist)
            end
            remove_from_list(self._tolist, id)
        end
    end
end

--- Removes the notification from this manager
---@param notification fltnotify.notification Notification id
function M:notification_delete(notification)
    local item = self:_validate_id(notification)
    self:notification_hide(notification)

    self._removed[notification] = true
    self._lblicon[notification] = nil
    if self._idas[notification] and self._anim then
        self._anim:animation_delete(self._idas[notification])
        self._aids[self._idas[notification]] = nil
        self._idas[notification] = nil
    end
    if item.timeout ~= false then
        self:_set_timeout(notification, false)
    end

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

---@package
function M:_update_win()
    local height = 0
    local width = 0
    local extmarks =
        vim.api.nvim_buf_get_extmarks(self._buf, self._ns, 0, -1, {})
    local count = 0
    for _, extm in pairs(extmarks) do
        local mw = self._lbllen[extm[1]] + self._items[extm[1]]:calc_width()
        self._items[extm[1]].lastwidth = mw
        width = math.max(width, mw, self._items[extm[1]].lastwidth)
        height = height + #self._items[extm[1]].message
        count = count + 1
    end
    local hassep = vim.fn.strwidth(self._cfg.separator) > 0
    if hassep and count > 1 then
        height = height + count - 1
    end
    if height <= 0 then
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
    local lblw = vim.fn.strwidth(label)
    if lblw > 0 then
        set_extm_lbl(extmark, label, hl_group)
        ws[#ws + 1] = { lblw, vim.fn.strwidth(vim.trim(label)) }
    end
    if self._lblicon[id] then
        local iconw = vim.fn.strwidth(self._lblicon[id])
        if iconw > 0 then
            set_extm_lbl(extmark, self._lblicon[id], hl_group)
            ws[#ws + 1] =
                { iconw, vim.fn.strwidth(vim.trim(self._lblicon[id])) }
        end
    end
    local smid, send = ' ', ' '
    if #item.message > 1 then
        if vim.fn.strwidth(self._cfg.separator) == 0 then
            smid, send = '│', '└'
        end
        for i = 2, #item.message - 1 do
            add_extm_line(extmark, item.message[i], ws, smid, hl_group)
        end
        add_extm_line(extmark, item.message[#item.message], ws, send, hl_group)
    end

    return extmark
end

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

local function prev_id(me, shown)
    local prev = me - 1
    while prev > 0 and not shown[prev] do
        prev = prev - 1
    end
    return prev >= 1 and prev or nil
end

local function update_virt_lines(buf, ns, id, line)
    local e =
        vim.api.nvim_buf_get_extmark_by_id(buf, ns, id, { details = true })
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
        vim.api.nvim_buf_set_extmark(buf, ns, e[1], e[2], em)
    end
end

---@package
---@param id fltnotify.notification
---@param hide boolean
function M:_update_buf(id, hide)
    local item = self:_validate_id(id)
    local sepw = vim.fn.strwidth(self._cfg.separator)
    if not hide then
        local label = self._cfg.level[item.level].label
        local hl_group = self._cfg.level[item.level].hl_group
        local line, update = get_notification_line(self._buf, self._ns, id)
        local extm = self:_prepare_extmark(id, item, label, hl_group)
        self._lbllen[id] = vim.iter(extm.virt_text):fold(0, function(n, chunk)
            return n + vim.fn.strwidth(chunk[1])
        end)

        if sepw > 0 then
            if line > 0 and not update then
                local prev = prev_id(id, self._shown)
                update_virt_lines(self._buf, self._ns, prev, {
                    self._cfg.separator:rep(math.ceil(vim.o.columns / sepw)),
                })
            elseif line < vim.api.nvim_buf_line_count(self._buf) - 1 then
                table.insert(extm.virt_lines, {
                    {
                        self._cfg.separator:rep(
                            math.ceil(vim.o.columns / sepw)
                        ),
                    },
                })
            end
        end

        vim.api.nvim_buf_set_lines(
            self._buf,
            line,
            line + (update and 1 or 0),
            true,
            { item.message[1] }
        )
        vim.api.nvim_buf_set_extmark(self._buf, self._ns, line, 0, extm)
    else
        local em =
            vim.api.nvim_buf_get_extmark_by_id(self._buf, self._ns, id, {})
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

    local id = self:create_notification()
    self:notification_show(id, msg, opts)
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
    ---Creates a new notification manager
    ---@param config fltnotify.config
    ---@return fltnotify.manager
    new = function(config)
        local cfg = require('fltnotify.config').get(config)
        local mgr
        mgr = {
            _cfg = cfg,
            _items = {},
            _ns = vim.api.nvim_create_namespace(''),
            _buf = vim.api.nvim_create_buf(false, true),
            _removed = {},
            _once = {},
            _lbllen = {},
            _lblicon = {},
            _aids = {},
            _totimer = vim.uv.new_timer(),
            _tolist = {},
            _idas = {},
            _shown = {},
            _ianim = {},
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
                        if id and not mgr._removed[id] then
                            mgr._lblicon[id] = item.frame
                            mgr:_update_buf(id, #mgr._items[id].message == 0)
                        end
                    end
                    mgr:_update_win()
                end)
            )
        else
            mgr._danim = {}
            for i = 0, 1000 do
                mgr._danim[i] = ('%3.1f%%'):format(i / 10)
            end
        end
        mgr._tocb = vim.schedule_wrap(function(notification)
            mgr:notification_delete(notification)
        end)
        return setmetatable(mgr, M)
    end,
}
