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

---@package
---@enum fltnotify.progress_alias
local progress_type_alias = {
    number = 'deter',
    boolean = 'indet',
}

---@package
---@return fltnotify.progress_alias
function I:get_progress_type()
    return progress_type_alias[type(self.progress)]
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
---@field private _psyms { deter: table, indet: table }
---@field private _pdurs { deter: number, indet: number }
---@field private _anim fltanim.runner
---@field private _aids table<fltanim.animation, fltnotify.notification>
---@field private _idas table<fltnotify.notification, fltanim.animation>
---@field private _once table<string, boolean>
---@field private _touts table<fltnotify.notification, uv.uv_timer_t>
---@field private _win? integer
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

---@package
function M:animate(items)
    for _, item in ipairs(items) do
        local id, frame = item.id, item.frame
        local notification = self._aids[id]
        if notification then
            item = self._items[notification]
            local ptype = item:get_progress_type()
            assert(
                frame > 0 and frame <= #self._psyms[ptype],
                'bad frame#: ' .. frame
            )
            self._pframe[notification] = frame
            if self:visible(notification) then
                local ok, err =
                    pcall(self.notification_show, self, notification)
                if not ok then
                    vim.api.nvim_echo({ { err } }, true, { err = true })
                    self._anim:animation_delete(id)
                end
            end
        end
    end
end

--- Creates a new notification
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
    self:_update_buf(notification, hide)
    self:_update_win()

    if not hide and item.progress == true then
        if not self._idas[notification] then
            local aid = self._anim:create_animation({
                frames = #self._psyms.indet,
                duration = self._pdurs.indet,
            })
            self._aids[aid] = notification
            self._idas[notification] = aid
        elseif self._anim:animation_is_paused(self._idas[notification]) then
            self._anim:animation_unpause(self._idas[notification])
        end
    end

    if not hide and item.timeout then
        if not self._touts[notification] then
            self._touts[notification] = assert(vim.uv.new_timer())
        end
        if not self._touts[notification]:is_active() then
            local timeout = self:_resolve_timeout(notification)
            self._touts[notification]:start(timeout, 0, function()
                self._touts[notification]:close()
                self._touts[notification] = nil
                vim.schedule(function()
                    local aid = self._idas[notification]
                    if aid then
                        self._anim:animation_pause(aid)
                    end
                    self:notification_hide(notification)
                end)
            end)
        end
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
    end
end

---@private
---@param id fltnotify.notification
---@param progress fltnotify.progress_value
function M:_set_progress(id, progress)
    local item = self._items[id]
    item.progress = progress
    if progress == true then
        self._pframe[id] = self._pframe[id] or 1
        if self._pframe[id] > #self._psyms.indet then
            self._pframe[id] = 1
        end
    elseif progress ~= 'done' then
        if self._idas[id] then
            self._anim:animation_delete(self._idas[id])
            self._idas[id] = nil
        end
        local pv = math.max(0, math.floor(progress * (#self._psyms.deter - 1)))
        self._pframe[id] = pv + 1
    else
        -- if done, we also remove the animation
        if self._idas[id] then
            self._anim:animation_delete(self._idas[id])
            self._idas[id] = nil
        end
        self._pframe[id] = nil
    end
end

---@private
---@param id fltnotify.notification
---@param timeout number|false
function M:_set_timeout(id, timeout)
    local item = self._items[id]
    item.timeout = timeout
    if not timeout then
        if self._touts[id] then
            self._touts[id]:stop()
            if self._touts[id]:is_closing() then
                self._touts[id]:close()
            end
            self._touts[id] = nil
        end
    end
end

--- Removes the notification from this manager
---@param notification fltnotify.notification Notification id
function M:notification_delete(notification)
    self:_validate_id(notification)
    self:notification_hide(notification)

    self._removed[notification] = true
    if self._idas[notification] then
        self._anim:animation_delete(self._idas[notification])
        self._aids[self._idas[notification]] = nil
        self._idas[notification] = nil
    end
    self._pframe[notification] = nil
    if self._touts[notification] then
        self._touts[notification]:stop()
        if not self._touts[notification]:is_closing() then
            self._touts[notification]:close()
        end
        self._touts[notification] = nil
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
    local em =
        vim.api.nvim_buf_get_extmark_by_id(self._buf, self._ns, notification, {
            details = true,
        })
    return #em > 0 and em[1] < em[3].end_row
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
        if extm[2] < extm[4].end_row then
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

---@private
---@return string
function M:_make_label(id)
    local item = self._items[id]
    local cfglvl = self._cfg.level[item.level]
    if not item.progress then
        return cfglvl.label
    elseif item.progress ~= 'done' then
        local frame = self._psyms[item:get_progress_type()][self._pframe[id]]
        if frame == nil then
            vim.print(self._psyms, item:get_progress_type(), id, self._pframe)
            error('[fltnotify:progress] no frame to render', 2)
        end
        return frame
    else
        return '✓'
    end
end

---@private
---@param id fltnotify.notification
---@param hide boolean
function M:_update_buf(id, hide)
    local item = self._items[id]
    local start = 0
    local oldlen = 0

    ---@type number|boolean
    local seplen = vim.fn.strwidth(self._cfg.separator)

    do
        local em = vim.api.nvim_buf_get_extmark_by_id(self._buf, self._ns, id, {
            details = true,
        })
        if #em > 0 then
            -- updating notification
            start = em[1]
            oldlen = math.max(0, (em[3].end_row or start) - start)
        else
            -- showing notification
            if hide then
                return
            end
            local ems =
                vim.api.nvim_buf_get_extmarks(self._buf, self._ns, 0, -1, {
                    details = true,
                })
            for _, m in ipairs(ems) do
                if m[1] < id and m[2] < m[4].end_row then
                    start = m[4].end_row or start
                end
            end
        end
    end

    ---@type vim.api.keyset.set_extmark
    local extmark = {
        id = id,
        end_col = 0,
        hl_group = self._cfg.level[item.level].hl_group,
    }
    if not hide then
        local label = self:_make_label(id)
        local hl = extmark.hl_group
        if type(hl) == 'string' then
            hl = vim.api.nvim_get_hl_id_by_name(extmark.hl_group)
        end
        local lvllblw = vim.fn.strwidth(label)
        self._lbllen[id] = lvllblw

        if lvllblw > 0 then
            extmark.virt_text = { { label .. ' ', hl } }
            extmark.virt_text_pos = 'inline'
            self._lbllen[id] = lvllblw + 1
        end

        if #item.message > 1 then
            extmark.virt_lines = {}
            -- first accommodate
            if seplen > 0 then
                for i = 1, #item.message - 1 do
                    extmark.virt_lines[i] = {
                        { (' '):rep(self._lbllen[id]), hl },
                    }
                end
            else
                -- multiline message get indicator if no separator
                if lvllblw == 0 then
                    table.insert(extmark.virt_text, { '┌ ', hl })
                    self._lbllen[id] = self._lbllen[id] + 2
                end
                for i = 1, #item.message - 2 do
                    extmark.virt_lines[i] = {
                        { (' '):rep(self._lbllen[id] - 1) },
                        { '│ ', hl },
                    }
                end
                table.insert(extmark.virt_lines, {
                    { (' '):rep(self._lbllen[id] - 1) },
                    { '└ ', hl },
                })
            end

            -- add notification text now
            for i = 1, #item.message - 1 do
                table.insert(extmark.virt_lines[i], {
                    item.message[i + 1],
                    hl,
                })
            end
        end

        extmark.end_row = start + 1

        vim.api.nvim_buf_set_lines(self._buf, start, start + oldlen, true, {
            item.message[1],
        })
    else
        vim.api.nvim_buf_set_lines(self._buf, start, start + oldlen, true, {})
    end
    vim.api.nvim_buf_set_extmark(self._buf, self._ns, start, 0, extmark)

    -- update separators
    if seplen > 0 then
        local ems = vim.api.nvim_buf_get_extmarks(self._buf, self._ns, 0, -1, {
            details = true,
        })
        if #ems < 2 then
            return
        end

        local sep =
            { self._cfg.separator:rep(math.ceil(vim.o.columns / seplen)) }
        local last_start = vim.api.nvim_buf_line_count(self._buf)
        for i = #ems, 1, -1 do
            local em = ems[i]
            if em[2] < em[4].end_row then
                if em[4].end_row + 1 ~= last_start then
                    vim.api.nvim_buf_set_lines(
                        self._buf,
                        em[4].end_row,
                        last_start,
                        true,
                        sep
                    )
                end
                last_start = em[2]
            end
        end
        if last_start > 0 then
            vim.api.nvim_buf_set_lines(self._buf, 0, last_start, true, {})
        end
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
    if other_data.timeout then
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
    self._anim:stop()
    for _, timeout in pairs(self._touts) do
        timeout:stop()
        if not timeout:is_closing() then
            timeout:close()
        end
    end
    vim.api.nvim_buf_delete(self._buf, { unload = true })
end

return {
    new = function(config)
        local cfg = require('fltnotify.config').get(config)
        local mgr
        local on_frame = vim.schedule_wrap(function(items)
            mgr:animate(items)
        end)
        local syms, durs = require('fltnotify.symbols').build(cfg)
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
            _anim = require('fltanim').new(
                cfg.progress_animation.fps,
                on_frame
            ),
            _touts = {},
            _idas = {},
            _psyms = syms,
            _pdurs = durs,
        }
        return setmetatable(mgr, M)
    end,
}
