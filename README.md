# fltnotify.nvim

A notification widget for neovim.

## Requirements

- neovim >= 0.11.0

### Dependencies

- fltanim.nvim (optional): uses animations on progress display
- fltprogr.nvim (optional): adds a progress display for 'lsp'

## Instalation

Use your favorite way to install this plugin.

## Setup

You might as well use

```lua
vim.g.fltnotify_config = {}
```

or

```vim
let g:fltnotify_config = { }
```

or pass the configuration table to the `setup()` function.

## Configuration

The widget accepts the following keys:

```lua
-- default configuration
{
    -- Time in milliseconds before removing a notification
    timeout = 5000,
    -- Widget position in editor
    anchor = 'NE',            -- 'NW'|'NE'|'SW'|'SE' 
    -- Widget window border
    border = vim.o.winborder, -- ''|'bold'|'none'|'single'|'double'|'rounded'|'solid'|'shadow'|string[]
    -- Widget window title
    title = nil,              -- string
    -- Widget window title position
    title_pos = 'left',       -- 'center', 'left', 'right'
    -- Notification item separator
    separator = '─',          -- string
    -- Widget margin from screen edge
    margin = { 1, 1 },        -- 2-tuple
    -- Progress animation configuration, used when fltanim.nvim and fltprogr.nvim are found
    progress_animation = {
        -- Defines symbols for indeterminate progress visualization
        indeterminate = 'dot_spinner', -- See `fltanim.animations`
        -- Defines symbols for determinate progress visualization
        determinate = 'vbar_fill',     -- See `fltanim.animations`
        -- Animation fps
        fps = 20,
        -- Specify width of horizontal progress symbols
        width = 4,
    },
    -- Automatically replace `vim.notify` and `vim.notify_once` ?
    replace_system_notification = false,
    -- Notification level label and highlight configuration
    level = {
        -- log level TRACE
        [vim.log.levels.TRACE] = {
            label = '[T]',             -- string
            hl_group = 'DiagnosticOk', -- highlight name or id
        },
        -- log level DEBUG
        [vim.log.levels.DEBUG] = {
            label = '[D]',
            hl_group = 'DiagnosticHint',
        },
        -- log level INFO
        [vim.log.levels.INFO] = {
            label = '[I]',
            hl_group = 'DiagnosticInfo',
        },
        -- log level WARN
        [vim.log.levels.WARN] = {
            label = '[W]',
            hl_group = 'DiagnosticWarn',
        },
        -- log level ERROR
        [vim.log.levels.ERROR] = {
            label = '[E]',
            hl_group = 'DiagnosticError',
        },
        -- log level OFF
        [vim.log.levels.OFF] = {
            label = '',
            hl_group = 'Conceal',
        },
    },
}
```
