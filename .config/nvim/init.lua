-- ============================================================
-- Options
-- ============================================================

-- Line numbers
vim.opt.number         = true
vim.opt.relativenumber = true

-- Indentation
vim.opt.shiftwidth     = 4
vim.opt.tabstop        = 4
vim.opt.expandtab      = true
vim.opt.softtabstop    = 4

-- Centralize backups, swapfiles, and persistent undo
vim.opt.backupdir      = vim.fn.expand('~/.vim/backups')
vim.opt.directory      = vim.fn.expand('~/.vim/swaps')
vim.opt.undodir        = vim.fn.expand('~/.vim/undo')
vim.opt.undofile       = true

-- Don't back up files in tmp
vim.opt.backupskip     = '/tmp/*'

-- Modelines (e.g. fold markers)
vim.opt.modeline       = true
vim.opt.modelines      = 4

-- Per-directory .nvimrc files (with safety restrictions)
vim.opt.exrc           = true
vim.opt.secure         = true

-- Visual
vim.opt.cursorline     = true
vim.opt.title          = true
vim.opt.scrolloff      = 8

-- Show invisible characters
vim.opt.list           = true
vim.opt.listchars      = { tab = '▸ ', trail = '·', nbsp = '_' }

-- Search
vim.opt.ignorecase     = true
vim.opt.smartcase      = true

-- Behavior
vim.opt.startofline    = false
vim.opt.shortmess:append('I')

-- Wrap
vim.opt.wrap = true
vim.opt.linebreak = true

-- Clipboard
vim.opt.clipboard = "unnamedplus"


-- ============================================================
-- Keymaps
-- ============================================================

-- ------------------------------------------------------------
-- Prose buffers: make motion follow *visual* lines
-- ------------------------------------------------------------
-- `wrap` + `linebreak` are on globally, so a paragraph is one logical line
-- spanning many screen rows. Unmapped j/k step by logical line, i.e. they
-- jump the whole paragraph and vertical movement *inside* a paragraph is
-- unavailable. Same for 0/$, which go to the paragraph's ends rather than
-- the visible row's.
--
-- The v:count guard keeps counts operating on real lines, so `5j` still
-- means what relativenumber says it means. Bare j/k move visually.
local prose_ft = { 'markdown', 'rmd', 'text', 'tex', 'plaintex', 'typst', 'textile', 'mail' }

vim.api.nvim_create_autocmd('FileType', {
    pattern = prose_ft,
    callback = function(ev)
        local function map(lhs, rhs, expr)
            vim.keymap.set({ 'n', 'x' }, lhs, rhs,
                { buffer = ev.buf, expr = expr or false, silent = true })
        end

        -- Swap, don't override: the g-prefixed forms keep the *logical*-line
        -- behaviour so it stays reachable. `g$` = true end of paragraph.
        map('j', "v:count == 0 ? 'gj' : 'j'", true)
        map('k', "v:count == 0 ? 'gk' : 'k'", true)
        map('0', 'g0')
        map('$', 'g$')
        map('^', 'g^')
        map('gj', 'j')
        map('gk', 'k')
        map('g0', '0')
        map('g$', '$')
        map('g^', '^')

        -- Wrapped rows keep the paragraph's indent instead of starting at col 0.
        vim.opt_local.breakindent = true

        -- Better sentence objects/motions (as/is, (, ), g(, g)) from
        -- vim-textobj-sentence: handles abbreviations like "Dr." and "e.g."
        -- that vim's native sentence regex splits on incorrectly.
        --
        -- Guard on the plugin's own load flag, NOT on exists('*textobj#...'):
        -- checking for an autoload function does not trigger the autoload, so
        -- that test reads 0 until something has already called into the file.
        if vim.g.loaded_textobj_sentence == 1 then
            pcall(vim.fn['textobj#sentence#init'])
        end
    end,
})

-- ------------------------------------------------------------
-- Markdown sections as a text object: ah / ih
-- ------------------------------------------------------------
-- The unit is treesitter's `section` node: a heading plus everything beneath
-- it up to the next heading of the same or a higher level, nested subsections
-- included. That is the range 'foldexpr' already computes, so `dah` and
-- `zc`+`dd` always agree.
--
--   ah  the whole section, heading line included -- the one for moving or
--       deleting a section wholesale
--   ih  its body: heading line dropped, blank lines trimmed off both ends,
--       matching how `ip` excludes the blank lines that `ap` takes
--
-- A count climbs outward through the nesting: standing in a `##` body, `d2ah`
-- takes the enclosing `#` section.
--
-- Nothing native covers this. The runtime markdown ftplugin maps `]]`/`[[` in
-- normal and visual mode only, never operator-pending, so `d]]` falls through
-- to the builtin section motion and quietly deletes to end of file; mkdnflow's
-- `]]` and `][` are normal-mode-only for the same reason. And `az` from
-- nvim-various-textobjs deliberately adds a line past the fold, which here is
-- the *next* heading.
local function markdown_section(scope)
    local ok, parser = pcall(vim.treesitter.get_parser, 0, 'markdown')
    if not ok or not parser then
        vim.notify('no markdown treesitter parser for this buffer', vim.log.levels.WARN)
        return
    end
    -- Parse eagerly rather than trusting the cached tree. On a `.` repeat the
    -- operator has already edited the buffer while the tree is still the
    -- pre-edit one, and its ranges then point past the last line.
    parser:parse(true)

    local node = vim.treesitter.get_node()
    if not node then return end

    -- Climb to the v:count1-th enclosing section. Reading the count here (not
    -- from the mapping) is what makes `2ah` differ from `ah`; operator-pending
    -- counts multiply, so `d2ah` and `2dah` both arrive as 2.
    local section
    for _ = 1, vim.v.count1 do
        while node and node:type() ~= 'section' do
            node = node:parent()
        end
        if not node then
            vim.notify('not inside a markdown section', vim.log.levels.WARN)
            return
        end
        section, node = node, node:parent()
    end

    -- The installed grammar does not open a section at a setext heading (the
    -- `===`/`---` underlined form) -- it leaves those as plain children of the
    -- surrounding section, so a setext-headed document parses as a single
    -- section and `ah` would silently swallow the lot. Say so instead; a
    -- message beats undoing a whole-file delete.
    for child in section:iter_children() do
        if child:type() == 'setext_heading' then
            vim.notify('setext headings are not sectioned by the parser; use ATX (#) headings',
                vim.log.levels.WARN)
            return
        end
    end

    -- Treesitter end positions are exclusive, and a section followed by another
    -- heading ends at column 0 of that heading's line -- so the last line of
    -- the object is `erow` itself, not `erow + 1`. The other case is a section
    -- running to a final line with no trailing newline.
    local srow, _, erow, ecol = section:range()
    local first = srow + 1
    local last = math.min((ecol == 0) and erow or erow + 1, vim.api.nvim_buf_line_count(0))

    if scope == 'inner' then
        -- Skip the heading, taking its extent from the node instead of
        -- assuming one line. A section holding the preamble before the first
        -- heading has no heading child, and then there is nothing to skip.
        local head = section:child(0)
        if head and head:type() == 'atx_heading' then
            local _, _, hrow, hcol = head:range()
            first = (hcol == 0) and hrow + 1 or hrow + 2
        end
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        local blank = function(n) return lines[n] == nil or lines[n]:find('^%s*$') ~= nil end
        while first <= last and blank(first) do first = first + 1 end
        while last >= first and blank(last) do last = last - 1 end
        if first > last then
            vim.notify('section has no body', vim.log.levels.WARN)
            return
        end
    end

    -- Linewise selection: land on the first line, start (or reuse) V, hop to
    -- the anchor with `o` so the cursor end is free, then extend to the last.
    vim.api.nvim_win_set_cursor(0, { first, 0 })
    if vim.fn.mode() ~= 'V' then
        vim.cmd.normal { 'V', bang = true }
    end
    vim.cmd.normal { 'o', bang = true }
    vim.api.nvim_win_set_cursor(0, { last, 0 })
end

vim.api.nvim_create_autocmd('FileType', {
    pattern = { 'markdown', 'rmd' },
    callback = function(ev)
        for lhs, scope in pairs { ah = 'outer', ih = 'inner' } do
            vim.keymap.set({ 'o', 'x' }, lhs, function() markdown_section(scope) end,
                { buffer = ev.buf, silent = true, desc = scope .. ' markdown section' })
        end
    end,
})

-- ------------------------------------------------------------
-- Move lines up/down: <A-j> / <A-k>
-- ------------------------------------------------------------
-- `:move` rather than dd+p: the unnamed register survives, and the whole
-- thing is one undo step instead of two.
--
-- The address arithmetic is asymmetric because `:m {addr}` places the line
-- *after* addr while the line being moved still occupies its slot during
-- address resolution. So down-by-n is `.+n`, but up-by-n has to clear its
-- own slot too and is `.-(n+1)`. Address 0 means "before line 1".
--
-- Clamping to the buffer ends instead of letting E16 fire keeps a held-down
-- key from beeping at the top and bottom.
--
-- No `==` reindent, unlike the mappings this is usually written as. It is
-- right for code and wrong for the prose buffers above, where `=` has no
-- useful indentexpr and will flatten deliberate leading whitespace.
local function move_lines(dir)
    return function()
        local n = vim.v.count1
        local last = vim.api.nvim_buf_line_count(0)
        local line, col = unpack(vim.api.nvim_win_get_cursor(0))
        local dest = (dir == 'down') and math.min(line + n, last) or math.max(line - n - 1, 0)
        if dest == ((dir == 'down') and line or line - 1) then return end
        vim.cmd('move ' .. dest)
        -- `:move` leaves the cursor on the first non-blank; keep the column
        -- instead, which is what makes this feel like the editor version.
        vim.api.nvim_win_set_cursor(0, { vim.fn.line('.'), col })
    end
end

-- Visual mode needs the range spelled out as line numbers: `'<` and `'>` are
-- only written when visual mode *exits*, so inside the mapping they still
-- hold the previous selection, or are unset entirely (E20).
local function move_visual(dir)
    return function()
        local n = vim.v.count1
        local last = vim.api.nvim_buf_line_count(0)
        -- The selection's two ends: `v` is the anchor, `.` the cursor. Track
        -- them separately so the cursor stays on the end it started on, and
        -- so a selection made bottom-up keeps its direction.
        local a_line, a_col = vim.fn.line('v'), vim.fn.col('v') - 1
        local c_line, c_col = vim.fn.line('.'), vim.fn.col('.') - 1
        local s, e = math.min(a_line, c_line), math.max(a_line, c_line)

        local dest, shift
        if dir == 'down' then
            dest  = math.min(e + n, last)
            shift = dest - e
        else
            dest  = math.max(s - n - 1, 0)
            shift = dest - (s - 1)
        end
        if shift == 0 then return end -- clamped at a buffer edge; leave the
        -- selection untouched

        vim.cmd(string.format('silent %d,%dmove %d', s, e, dest))

        -- Still in visual mode here: `:move` does not end it, and `normal! V`
        -- at this point would *toggle it off* -- which drops the next press
        -- through to the normal-mode mapping. So shift the two ends in place
        -- instead of reselecting. Setting the cursor moves whichever end is
        -- active; `o` swaps which one that is. This also preserves charwise
        -- and blockwise selections, since the mode is never touched.
        local function put(line, col)
            local len = #vim.fn.getline(line)
            vim.api.nvim_win_set_cursor(0, { line, math.min(col, math.max(len - 1, 0)) })
        end
        put(a_line + shift, a_col)
        vim.cmd.normal { 'o', bang = true }
        put(c_line + shift, c_col)
    end
end

for lhs, dir in pairs { ['<A-j>'] = 'down', ['<A-k>'] = 'up' } do
    vim.keymap.set('n', lhs, move_lines(dir), { desc = 'Move line ' .. dir })
    vim.keymap.set('x', lhs, move_visual(dir), { desc = 'Move selection ' .. dir })
end

-- ------------------------------------------------------------
-- Genizah: `dd` appends to archive/<same name> before deleting
-- ------------------------------------------------------------
-- A deleted todo item is not worthless, it is just done with -- so instead of
-- letting `dd` drop it into the unnamed register to be overwritten by the next
-- one, copy it into a same-named file under a sibling archive/ directory.
--
-- The switch is the archive file's *existence*: nothing is created, so `dd`
-- stays exactly `dd` everywhere except the handful of files you have opted in
-- by running `touch archive/<name>` next to them. That also means the feature
-- fails closed -- a typo'd filename archives nothing rather than scattering
-- stray files around the tree.
--
-- Deliberately only `dd`. `V`+`d`, `:g/^- \[x\]/d`, `dap` and friends stay
-- destructive; `dd` is the one that maps onto "retire this item".
--
-- Two known holes, both accepted:
--   * `dd` then `p` to *move* a line still archives it. False positives are
--     the cheap failure for a genizah, and <A-j>/<A-k> above are the real
--     move-a-line binding anyway.
--   * `.` repeating a `dd` does not archive: dot replays the recorded change,
--     not the mapping. Closing that needs operatorfunc+g@ and a hand-rolled
--     reimplementation of dd's register/mark/undo semantics.
local function genizah_target()
    -- Only real files on disk. Terminals, netrw listings and scratch buffers
    -- have no meaningful sibling directory.
    if vim.bo.buftype ~= '' then return nil end
    local file = vim.api.nvim_buf_get_name(0)
    if file == '' then return nil end
    file = vim.fn.fnamemodify(file, ':p')

    local target = vim.fn.fnamemodify(file, ':h') .. '/archive/'
        .. vim.fn.fnamemodify(file, ':t')
    -- Editing the genizah itself: deleting from it must not re-append to it.
    if target == file then return nil end

    local st = vim.uv.fs_stat(target)
    if not st or st.type ~= 'file' then return nil end
    return target
end

local function genizah_append(target, lines)
    -- Whether a separator newline is needed depends on the last byte already
    -- there; appending blind to a file with no trailing newline would splice
    -- the first archived line onto the end of the previous one. An empty file
    -- needs no separator, hence the '\n' default.
    local last = '\n'
    local f = io.open(target, 'rb')
    if f then
        local size = f:seek('end')
        if size > 0 then
            f:seek('set', size - 1)
            last = f:read(1)
        end
        f:close()
    end

    f = assert(io.open(target, 'ab'))
    if last ~= '\n' then f:write('\n') end
    f:write(table.concat(lines, '\n'), '\n')
    f:close()
end

-- An <expr> mapping rather than a function that runs `normal! dd` itself: the
-- keys are handed back to be executed as typed, so this *is* native dd, with
-- its registers ("add still works), marks, folds and 'clipboard' behaviour
-- intact. A count typed before a mapping stays pending and applies to the
-- first command of the RHS, so `3dd` arrives here as v:count1 == 3 and then
-- executes as `3dd` -- the same mechanism the j/k prose maps above rely on.
vim.keymap.set('n', 'dd', function()
    -- 'nomodifiable' would make the dd itself fail; archiving first would then
    -- file away a line that is still in the buffer.
    local target = genizah_target()
    if not target or not vim.bo.modifiable then return 'dd' end

    local first = vim.api.nvim_win_get_cursor(0)[1]
    -- `false` for strict_indexing: near the end of the buffer, `5dd` deletes
    -- only what is left, and the read has to clamp the same way.
    local lines = vim.api.nvim_buf_get_lines(0, first - 1, first - 1 + vim.v.count1, false)

    -- Blank lines are not worth burying -- but only skip when the *whole*
    -- deletion is blank, so a multi-line block keeps its internal spacing.
    local empty = true
    for _, l in ipairs(lines) do
        if l:find('%S') then
            empty = false
            break
        end
    end

    if not empty then
        local ok, err = pcall(genizah_append, target, lines)
        if not ok then
            -- Deferred: notifying from inside an <expr> evaluation gets eaten
            -- by the redraw that follows the mapping.
            vim.schedule(function()
                vim.notify('genizah: ' .. tostring(err), vim.log.levels.ERROR)
            end)
        end
    end

    return 'dd'
end, { expr = true, silent = true, desc = 'Delete line, archiving it if archive/<file> exists' })

-- <C-c> in visual mode to yank to the system clipboard, because "+y is three
-- shifted keys away and the pinky has other jobs. Only 'x' (visual), never
-- insert or normal: there <C-c> is the interrupt/Esc-without-InsertLeave, and
-- it is the one key guaranteed to get you out of whatever you are in.
-- Losing <C-c>-as-exit-visual costs nothing; Esc and v both still do it.
vim.keymap.set('x', '<C-c>', '"+y', { desc = 'Yank selection to system clipboard' })

-- <C-s> as Esc. Colemak puts Backspace on Caps Lock, so the usual remap-Caps-
-- to-Esc trick is unavailable, and every <mod>+Space is taken (caps typing,
-- cmp's menu, the WM). The terminal never swallows it as XOFF: nvim runs the
-- tty raw, which turns flow control off while it is in the foreground.
--
-- Costs: nvim 0.11+'s default insert/select <C-s>, LSP signature help. In the
-- command line it is <C-c>, not <Esc>, which is the key that reliably
-- *abandons* the line there instead of risking running it.
vim.keymap.set({ 'i', 'x', 's' }, '<C-s>', '<Esc>', { desc = 'Exit to normal mode' })
vim.keymap.set('c', '<C-s>', '<C-c>', { desc = 'Abandon command line' })

-- Strip trailing whitespace (<leader>ss)
vim.keymap.set('n', '<leader>ss', function()
    local pos = vim.api.nvim_win_get_cursor(0)
    vim.cmd([[%s/\s\+$//e]])
    vim.api.nvim_win_set_cursor(0, pos)
end, { desc = 'Strip trailing whitespace' })

-- Save file as root (<leader>W)
vim.keymap.set('n', '<leader>W', ':w !sudo tee % > /dev/null<CR>', { desc = 'Save file as root' })

-- Go back (<BS>), in order of specificity:
--   1. mkdnflow's link history, when following markdown links
--   2. netrw's :Rex[plore] -- the directory listing the file was opened from
--   3. the default <BS> motion
-- netrw ships 2. as :Rex; from inside a listing it flips back to the file, so
-- that step is a toggle. <C-^> reaches it via the alternate buffer, and `-`
-- inside a listing goes up one directory.
--
-- Both steps are tested by inspecting state rather than by calling and
-- catching: goBack() emits its own "can't go back any further" warning on an
-- empty stack, and :Rexplore only *notifies* when there is no listing to
-- return to (netrw.vim, `com! Rexplore`) rather than raising, so pcall would
-- report success and swallow the fallback.
vim.keymap.set('n', '<BS>', function()
    local ok, buffers = pcall(require, 'mkdnflow.buffers')
    if ok and buffers.main and #buffers.main > 0 and buffers.goBack() then
        return
    end
    if vim.w.netrw_rexlocal ~= nil then
        vim.cmd('Rexplore')
        return
    end
    vim.cmd('normal! ' .. vim.keycode('<BS>'))
end, { desc = 'Back: mkdnflow history -> netrw listing -> motion' })

-- <leader>p to execute python file
vim.api.nvim_create_autocmd('FileType', {
    pattern = 'python',
    callback = function()
        vim.keymap.set('n', '<leader>p', function()
            local t = vim.uv.hrtime
            local t0 = t()
            vim.cmd('w')
            print('write: ' .. (t() - t0) / 1e6 .. 'ms')
            t0 = t()
            local file = vim.fn.expand('%:p')
            vim.cmd('noautocmd split')
            print('split: ' .. (t() - t0) / 1e6 .. 'ms')
            t0 = t()
            local win = vim.api.nvim_get_current_win()
            local buf = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_win_set_buf(win, buf)
            vim.fn.termopen({ 'python3', file })
            print('termopen: ' .. (t() - t0) / 1e6 .. 'ms')
        end, { buffer = true, desc = 'Run Python file' })
    end,
})

-- ============================================================
-- lazy.nvim bootstrap
-- ============================================================

local lazypath = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
if not vim.loop.fs_stat(lazypath) then
    vim.fn.system({
        'git', 'clone', '--filter=blob:none',
        'https://github.com/folke/lazy.nvim.git',
        '--branch=stable',
        lazypath,
    })
end
vim.opt.rtp:prepend(lazypath)


-- ============================================================
-- Plugins
-- ============================================================

-- Core plugins: always loaded. These need no external toolchain beyond a
-- C compiler for treesitter parsers (installed by bootstrap.sh).
local plugins = {

    -- Treesitter: parser installer + queries. Now on the `main` branch (the
    -- current rewrite targeting Neovim 0.12). Highlighting/folding are native
    -- on 0.12, so this no longer needs the old nvim-treesitter.configs API.
    -- Requires tree-sitter-cli in PATH.
    {
        'nvim-treesitter/nvim-treesitter',
        lazy = false, -- main branch does not support lazy-loading
        build = ':TSUpdate',
        config = function()
            require('nvim-treesitter').setup {
                install_dir = vim.fn.stdpath('data') .. '/site',
            }
            require('nvim-treesitter').install {
                'markdown', 'markdown_inline',
                'python', 'typescript', 'tsx', 'rust', 'lua',
                'c', 'cpp',
                'typst',
                -- fenced-code-block languages; main branch has no auto_install,
                -- so add any you use (e.g. bash for ```sh) here or via :TSInstall.
                'bash',
            }
            vim.opt.foldmethod = 'expr'
            vim.opt.foldexpr   = 'v:lua.vim.treesitter.foldexpr()'
            vim.opt.foldenable = false -- open all folds by default
            vim.api.nvim_create_autocmd('FileType', {
                callback = function(ev)
                    -- vimtex does its own syntax (math-zone detection, conceal)
                    -- and breaks if treesitter takes over highlighting.
                    if vim.bo[ev.buf].filetype == 'tex' then return end
                    if pcall(vim.treesitter.start, ev.buf) then
                        -- treesitter indent is still experimental, and cindent is
                        -- better for C-family, so only use it elsewhere
                        if not vim.tbl_contains({ 'c', 'cpp' }, vim.bo[ev.buf].filetype) then
                            vim.bo[ev.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
                        end
                    end
                end,
            })
        end,
    },

    -- Markdown rendering
    {
        'MeanderingProgrammer/render-markdown.nvim',
        config = function()
            require('render-markdown').setup {}

            -- Keep literal Markdown delimiters visible: shell-style paths and
            -- identifiers such as sgtr_em or ~$2.4/run should not disappear.
            vim.api.nvim_create_autocmd('FileType', {
                pattern = { 'markdown', 'rmd' },
                callback = function()
                    vim.opt_local.conceallevel = 0
                end,
            })
        end,
    },

    -- Markdown flow
    {
        'jakewvincent/mkdnflow.nvim',
        ft = { 'markdown', 'rmd' }, -- Add custom filetypes here if configured
        config = function()
            require('mkdnflow').setup({
                -- mkdnflow maps <BS> to MkdnGoBack buffer-locally, and
                -- buffer-local mappings win over global ones, so it shadowed
                -- the <BS> mapping in the Keymaps section above. Disable it
                -- here; that mapping calls goBack() itself as its first step,
                -- so link-history navigation still works.
                mappings = {
                    MkdnGoBack = false,
                },
            })
        end
    },

    -- Statusline with mode colors
    {
        'nvim-lualine/lualine.nvim',
        config = function()
            require('lualine').setup({
                options = {
                    theme = 'auto',
                },
            })
        end,
    },

    -- Label-based jumps: `s` + 2 chars, then a label, to reach any visible
    -- position. Composes with operators (`dsth` = delete to that spot) and
    -- works as a visual-mode target. This is the piece that makes keyboard
    -- motion beat pointing for arbitrary targets.
    --
    -- Costs: normal/visual `s` (== `cl` / `c`, use those) and normal `S`
    -- (== `cc`). `S` here is treesitter-node select: press repeatedly to
    -- grow the selection outward through the syntax tree.
    {
        'folke/flash.nvim',
        event = 'VeryLazy',
        opts = {
            -- Labels are typed on the physical layout in use, so this is the
            -- Colemak home row first, then the easiest remaining keys.
            labels = 'arstdhneiogmvcxzwfpblu',
            modes = {
                -- Don't hijack f/F/t/T or `/`; keep those behaving normally.
                char = { enabled = false },
                search = { enabled = false },
            },
        },
        keys = {
            { 's', mode = { 'n', 'x', 'o' }, function() require('flash').jump() end,       desc = 'Flash jump' },
            { 'S', mode = { 'n', 'x', 'o' }, function() require('flash').treesitter() end, desc = 'Flash treesitter select' },
        },
    },

    -- A real sentence text object. The sentence is the unit of prose revision
    -- (`das` kill, `cas` rewrite, `yas`+`p` duplicate-and-vary), and vim ships
    -- nothing between word and paragraph. Enabled per-filetype by the prose
    -- autocmd above; both are tiny vimscript plugins, so load eagerly rather
    -- than fight lazy-load ordering with the autocmd.
    { 'kana/vim-textobj-user',          lazy = false },
    { 'preservim/vim-textobj-sentence', lazy = false, dependencies = { 'kana/vim-textobj-user' } },

    -- Assorted extra text objects. Most useful here: iq/aq (any quote type,
    -- including “smart” quotes), io/ao (any bracket), iS/aS (subword, stops at
    -- camelCase and snake_case boundaries), i_/a_ (line, charwise), iF/aF
    -- (filepath), gG (entire buffer).
    {
        'chrisgrieser/nvim-various-textobjs',
        lazy = false, -- required: default keymaps aren't applied when lazy-loaded
        opts = {
            keymaps = {
                useDefaults = true,
                -- Defaults claim some bare letters in operator-pending *and*
                -- visual mode, where they'd shadow commands worth keeping:
                --   n  next search match (extends a visual selection)
                --   !  filter selection through an external command
                --   C  R  change the selected lines
                --   r  replace every selected char
                --   .  |  low value as objects, and `.` is muscle-memorised
                disabledDefaults = { 'n', '!', 'C', 'R', 'r', '.', '|' },
            },
        },
        config = function(_, opts)
            require('various-textobjs').setup(opts)

            -- Recover the two useful objects disabled above, in
            -- operator-pending mode only, where nothing collides.
            vim.keymap.set('o', 'r', function()
                require('various-textobjs').restOfParagraph()
            end, { desc = 'rest of paragraph' })
            vim.keymap.set('o', 'n', function()
                require('various-textobjs').nearEoL()
            end, { desc = 'to near end of line' })
        end,
    },

    -- Auto pair delimiters
    {
        'windwp/nvim-autopairs',
        event = 'InsertEnter',
        opts = {},
        --opts = {
        --    disable_filetype = { 'TelescopePrompt', 'markdown', 'rmd', 'text', 'mail' },
        --},
    },

    -- Surround: add/delete/replace pairs around text. The other half of
    -- autopairs -- that one types pairs, this one edits existing ones.
    --
    -- Moved off the tpope-standard ys/ds/cs and visual S, because flash owns
    -- `s` in operator-pending mode (`dsth`) and `S` in visual. The gs prefix
    -- (LazyVim's answer to the same collision) costs only `gs`, which is
    -- :sleep. Since `gsa` is an operator, `gsa` + `s` + label surrounds from
    -- the cursor to a flash target.
    --
    --   gsa{motion}{char}  add          gsaiw) -> (word)   gsaiw( -> ( word )
    --   gsl{char}          add, line    gsA / visual gsA: on separate lines
    --   gsd{char}          delete       gsd" , gsdt (tag), gsdf (call)
    --   gsr{old}{new}      replace      gsr"' , gsrt<div> -> retag
    --
    -- v4 dropped the `keymaps` setup option: the plugin's own plugin/ file
    -- maps the defaults at load unless told not to, and custom keys bind to
    -- its <Plug> maps. Hence `init` (runs before load) for the opt-outs, and
    -- `remap` because <Plug> targets are themselves mappings. Insert-mode
    -- <C-g>s is left at its default.
    {
        'kylechui/nvim-surround',
        init = function()
            vim.g.nvim_surround_no_normal_mappings = true
            vim.g.nvim_surround_no_visual_mappings = true
        end,
        keys = {
            { 'gsa', '<Plug>(nvim-surround-normal)',      remap = true, desc = 'Surround add (motion)' },
            { 'gsl', '<Plug>(nvim-surround-normal-cur)',  remap = true, desc = 'Surround add (line)' },
            { 'gsA', '<Plug>(nvim-surround-normal-line)', remap = true, desc = 'Surround add, on new lines' },
            { 'gsd', '<Plug>(nvim-surround-delete)',      remap = true, desc = 'Surround delete' },
            { 'gsr', '<Plug>(nvim-surround-change)',      remap = true, desc = 'Surround replace' },
            { 'gsR', '<Plug>(nvim-surround-change-line)', remap = true, desc = 'Surround replace, on new lines' },
            { 'gsa', '<Plug>(nvim-surround-visual)',      remap = true, mode = 'x',                             desc = 'Surround selection' },
            { 'gsA', '<Plug>(nvim-surround-visual-line)', remap = true, mode = 'x',                             desc = 'Surround selection, on new lines' },
        },
    },

    -- Fuzzy finder over files, grep, buffers, help, LSP symbols... Uses the
    -- fzf binary (~/.fzf/bin) and rg/fd. Inside the picker: <C-j>/<C-k> or
    -- arrows move, <CR> opens, <C-v> vsplit, <C-s> split, <C-t> tab, <F1>
    -- lists the rest. (The picker is a terminal buffer, so the insert-mode
    -- <C-s>-as-Esc above does not reach it.)
    {
        'ibhagwan/fzf-lua',
        cmd = 'FzfLua',
        opts = {},
        keys = {
            { '<leader>ff', '<cmd>FzfLua files<cr>',                desc = 'Find files' },
            { '<leader>fg', '<cmd>FzfLua live_grep<cr>',            desc = 'Grep (live)' },
            { '<leader>fw', '<cmd>FzfLua grep_cword<cr>',           desc = 'Grep word under cursor' },
            { '<leader>fb', '<cmd>FzfLua buffers<cr>',              desc = 'Buffers' },
            { '<leader>fo', '<cmd>FzfLua oldfiles<cr>',             desc = 'Recent files' },
            { '<leader>fh', '<cmd>FzfLua helptags<cr>',             desc = 'Help tags' },
            { '<leader>fk', '<cmd>FzfLua keymaps<cr>',              desc = 'Keymaps' },
            { '<leader>fs', '<cmd>FzfLua lsp_document_symbols<cr>', desc = 'LSP symbols (file)' },
            { '<leader>fr', '<cmd>FzfLua resume<cr>',               desc = 'Resume last picker' },
            { '<leader>f/', '<cmd>FzfLua blines<cr>',               desc = 'Lines in buffer' },
        },
    },

    -- Git gutter signs, hunk navigation/staging, inline blame. ]h/[h rather
    -- than the README's ]c/[c, which are diff-mode's own hunk motions.
    {
        'lewis6991/gitsigns.nvim',
        event = { 'BufReadPre', 'BufNewFile' },
        opts = {
            on_attach = function(buf)
                local gs = require('gitsigns')
                local function map(mode, lhs, rhs, desc)
                    vim.keymap.set(mode, lhs, rhs, { buffer = buf, desc = desc })
                end
                map('n', ']h', function() gs.nav_hunk('next') end, 'Next git hunk')
                map('n', '[h', function() gs.nav_hunk('prev') end, 'Prev git hunk')
                map({ 'n', 'x' }, '<leader>hs', ':Gitsigns stage_hunk<cr>', 'Stage hunk (toggle)')
                map({ 'n', 'x' }, '<leader>hr', ':Gitsigns reset_hunk<cr>', 'Reset hunk')
                map('n', '<leader>hp', gs.preview_hunk_inline, 'Preview hunk')
                map('n', '<leader>hb', function() gs.blame_line({ full = true }) end, 'Blame line')
                map('n', '<leader>hB', gs.toggle_current_line_blame, 'Toggle inline blame')
                map('n', '<leader>hd', gs.diffthis, 'Diff against index')
            end,
        },
    },

    -- Pops up the possible continuations after a prefix key (`\`, `g`, `z`,
    -- `"`, ...), built from each mapping's `desc`. The cheap cure for
    -- forgetting the mappings in this file.
    {
        'folke/which-key.nvim',
        event = 'VeryLazy',
        opts = {
            spec = {
                { '<leader>f', group = 'find' },
                { '<leader>h', group = 'git hunks' },
                { '<leader>x', group = 'trouble' },
                { '<leader>l', group = 'latex (vimtex)' },
                { '<leader>t', group = 'typst' },
                { 'gs',        group = 'surround' },
            },
        },
    },

    -- Diagnostics/references/symbols as a navigable list. Mostly useful with
    -- the LSP stack on, but the quickfix view works regardless.
    {
        'folke/trouble.nvim',
        cmd = 'Trouble',
        opts = {},
        keys = {
            { '<leader>xx', '<cmd>Trouble diagnostics toggle<cr>',                        desc = 'Diagnostics (project)' },
            { '<leader>xb', '<cmd>Trouble diagnostics toggle filter.buf=0<cr>',           desc = 'Diagnostics (buffer)' },
            { '<leader>xs', '<cmd>Trouble symbols toggle focus=false<cr>',                desc = 'Symbols outline' },
            { '<leader>xr', '<cmd>Trouble lsp toggle focus=false win.position=right<cr>', desc = 'LSP defs/refs panel' },
            { '<leader>xq', '<cmd>Trouble qflist toggle<cr>',                             desc = 'Quickfix list' },
        },
    },

    -- LaTeX. vimtex: compile (latexmk, continuous), SyncTeX forward/inverse
    -- search, TeX-aware motions/objects/surround ops. Maps live under `\l`.
    -- Must not be lazy-loaded (its own docs), and it is cheap anyway: the
    -- heavy parts are autoloaded on the first .tex buffer.
    --
    -- zathura_simple rather than zathura: the plain method tracks the viewer's
    -- window through xdotool (to reuse one instance), which is X11-only and
    -- useless on this Wayland session. The cost is a possible second zathura
    -- on a repeated `\lv`. Inverse search (<C-click> in zathura) still works:
    -- vimtex launches zathura with `-x` pointing back at this nvim.
    {
        'lervag/vimtex',
        lazy = false,
        init = function()
            vim.g.vimtex_view_method = 'zathura_simple'
        end,
    },

    -- TeXpresso: live preview that re-renders *as you type*, unsaved buffer
    -- included, instead of on save. Not packaged for Void; build it from
    -- source (github.com/let-def/texpresso) and put `texpresso` +
    -- `texpresso-xetex` on PATH. Until then `cond` skips the plugin, so this
    -- file stays portable to machines without it. `:TeXpresso %` to start.
    {
        'let-def/texpresso.vim',
        cond = vim.fn.executable('texpresso') == 1,
        ft = 'tex',
        keys = {
            { '<leader>lp', '<cmd>TeXpresso %<cr>', ft = 'tex', desc = 'TeXpresso live preview' },
        },
    },

    -- Typst: live preview in the browser, updated as you type and scrolled
    -- to follow the cursor; click in the preview to jump the cursor there.
    -- Uses the system tinymist (xbps) instead of letting the plugin download
    -- its own copy. It still fetches websocat, its editor->preview pipe, into
    -- stdpath('data') on first use; Void does not package that.
    {
        'chomosuke/typst-preview.nvim',
        ft = 'typst',
        opts = {
            dependencies_bin = { tinymist = 'tinymist' },
        },
        keys = {
            { '<leader>tp', '<cmd>TypstPreviewToggle<cr>',     ft = 'typst', desc = 'Typst live preview' },
            { '<leader>ts', '<cmd>TypstPreviewSyncCursor<cr>', ft = 'typst', desc = 'Scroll preview to cursor' },
        },
    },
}

-- LSP / completion / formatting stack is opt-in per machine. Enable it by
-- setting NVIM_LSP=1 in the environment (e.g. in ~/.zshenv, which is not
-- tracked by the dotfiles repo, so toggling produces no git diff).
if os.getenv('NVIM_LSP') == '1' then
    vim.list_extend(plugins, require('lsp'))
end

require('lazy').setup(plugins)
