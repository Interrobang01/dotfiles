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
local prose_ft = { 'markdown', 'rmd', 'text', 'tex', 'plaintex', 'textile', 'mail' }

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

-- Strip trailing whitespace (<leader>ss)
vim.keymap.set('n', '<leader>ss', function()
    local pos = vim.api.nvim_win_get_cursor(0)
    vim.cmd([[%s/\s\+$//e]])
    vim.api.nvim_win_set_cursor(0, pos)
end, { desc = 'Strip trailing whitespace' })

-- Save file as root (<leader>W)
vim.keymap.set('n', '<leader>W', ':w !sudo tee % > /dev/null<CR>', { desc = 'Save file as root' })

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
                -- fenced-code-block languages; main branch has no auto_install,
                -- so add any you use (e.g. bash for ```sh) here or via :TSInstall.
                'bash',
            }
            vim.opt.foldmethod = 'expr'
            vim.opt.foldexpr   = 'v:lua.vim.treesitter.foldexpr()'
            vim.opt.foldenable = false -- open all folds by default
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
                -- Your config
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
    { 'kana/vim-textobj-user',            lazy = false },
    { 'preservim/vim-textobj-sentence',   lazy = false, dependencies = { 'kana/vim-textobj-user' } },

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

}

-- LSP / completion / formatting stack is opt-in per machine. Enable it by
-- setting NVIM_LSP=1 in the environment (e.g. in ~/.zshenv, which is not
-- tracked by the dotfiles repo, so toggling produces no git diff).
if os.getenv('NVIM_LSP') == '1' then
    vim.list_extend(plugins, require('lsp'))
end

require('lazy').setup(plugins)
