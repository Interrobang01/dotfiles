-- Colemak remappings: swap hnei <-> hjkl
-- This places movement keys where hjkl sit on a QWERTY layout.
--
-- Movement (Colemak hnei -> QWERTY hjkl):
--   n -> down  (was j)
--   e -> up    (was k)
--   i -> right (was l)
--
-- Displaced keys get the original hnei functions:
--   j -> next search match      (was n)
--   k -> end of word            (was e)
--   l -> insert mode            (was i)
--
-- h -> left stays unchanged in both layouts.


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


-- ============================================================
-- Keymaps
-- ============================================================

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

    -- Treesitter: syntax highlighting and code folding.
    -- Pinned to the `master` branch: its API (nvim-treesitter.configs) is what
    -- this config targets. The `main` branch is a rewrite with a different,
    -- incompatible setup API.
    {
        'nvim-treesitter/nvim-treesitter',
        branch = 'master',
        build = ':TSUpdate',
        config = function()
            require('nvim-treesitter.configs').setup({
                ensure_installed = {
                    'markdown', 'markdown_inline',
                    'python', 'typescript', 'tsx', 'rust', 'lua',
                },
                auto_install = true, -- install missing parsers when opening a file
                highlight = { enable = true },
            })
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
        end,
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

}

-- LSP / completion / formatting stack is opt-in per machine. Enable it by
-- setting NVIM_LSP=1 in the environment (e.g. in ~/.zshenv, which is not
-- tracked by the dotfiles repo, so toggling produces no git diff).
if os.getenv('NVIM_LSP') == '1' then
    vim.list_extend(plugins, require('lsp'))
end

require('lazy').setup(plugins)
