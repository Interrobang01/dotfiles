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
vim.opt.shiftwidth  = 4
vim.opt.tabstop     = 4
vim.opt.expandtab   = true
vim.opt.softtabstop = 4

-- Centralize backups, swapfiles, and persistent undo
vim.opt.backupdir = vim.fn.expand('~/.vim/backups')
vim.opt.directory = vim.fn.expand('~/.vim/swaps')
vim.opt.undodir   = vim.fn.expand('~/.vim/undo')
vim.opt.undofile  = true

-- Don't back up files in tmp
vim.opt.backupskip = '/tmp/*'

-- Modelines (e.g. fold markers)
vim.opt.modeline  = true
vim.opt.modelines = 4

-- Per-directory .nvimrc files (with safety restrictions)
vim.opt.exrc   = true
vim.opt.secure = true

-- Visual
vim.opt.cursorline = true
vim.opt.title      = true
vim.opt.scrolloff  = 8

-- Show invisible characters
vim.opt.list      = true
vim.opt.listchars = { tab = '▸ ', trail = '·', nbsp = '_' }

-- Search
vim.opt.ignorecase = true
vim.opt.smartcase  = true

-- Behavior
vim.opt.startofline = false
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

require('lazy').setup({

  -- Treesitter: syntax highlighting and code folding
  {
    'nvim-treesitter/nvim-treesitter',
    build = ':TSUpdate',
    config = function()
      require('nvim-treesitter').setup({
        ensure_installed = {
          'markdown', 'markdown_inline',
          'python', 'typescript', 'tsx', 'rust', 'lua',
        },
        auto_install = true,  -- install missing parsers when opening a file
      })
      vim.opt.foldmethod = 'expr'
      vim.opt.foldexpr   = 'v:lua.vim.treesitter.foldexpr()'
      vim.opt.foldenable = false  -- open all folds by default
    end,
  },

  -- Markdown rendering
  {
    'MeanderingProgrammer/render-markdown.nvim',
    config = function()
      require('render-markdown').setup {}
    end,
  },

  -- Mason: installs language servers, linters, formatters
  {
    'williamboman/mason.nvim',
    config = function()
      require('mason').setup()
    end,
  },

  -- Bridges mason and nvim's native LSP so installed servers auto-configure
  {
    'williamboman/mason-lspconfig.nvim',
    dependencies = { 'williamboman/mason.nvim', 'neovim/nvim-lspconfig' },
    config = function()
      require('mason-lspconfig').setup({
        ensure_installed = {
          'pyright',        -- Python
          'ts_ls',          -- TypeScript / JavaScript
          'rust_analyzer',  -- Rust
          'lua_ls',         -- Lua
        },
        automatic_installation = true,
      })

      local capabilities = require('cmp_nvim_lsp').default_capabilities()

      -- Configure each server using nvim 0.11+ native API
      for _, server in ipairs({ 'pyright', 'ts_ls', 'rust_analyzer', 'lua_ls' }) do
        vim.lsp.config(server, { capabilities = capabilities })
      end
      vim.lsp.enable({ 'pyright', 'ts_ls', 'rust_analyzer', 'lua_ls' })

      -- Keymaps applied when any LSP attaches to a buffer
      vim.api.nvim_create_autocmd('LspAttach', {
        callback = function(args)
          local opts = { buffer = args.buf }
          local map  = function(key, fn, desc)
            vim.keymap.set('n', key, fn, vim.tbl_extend('force', opts, { desc = desc }))
          end
          map('gd',         vim.lsp.buf.definition,    'Go to definition')
          map('gD',         vim.lsp.buf.declaration,   'Go to declaration')
          map('gr',         vim.lsp.buf.references,    'Find references')
          map('K',          vim.lsp.buf.hover,         'Hover docs')
          map('<leader>rn', vim.lsp.buf.rename,        'Rename symbol')
          map('<leader>ca', vim.lsp.buf.code_action,   'Code action')
          map('<leader>e',  vim.diagnostic.open_float, 'Show diagnostic')
          map('[d',         vim.diagnostic.goto_prev,  'Prev diagnostic')
          map(']d',         vim.diagnostic.goto_next,  'Next diagnostic')
        end,
      })
    end,
  },

  -- Autocompletion
  {
    'hrsh7th/nvim-cmp',
    dependencies = {
      'hrsh7th/cmp-nvim-lsp',   -- LSP source
      'hrsh7th/cmp-buffer',     -- buffer words
      'hrsh7th/cmp-path',       -- filesystem paths
    },
    config = function()
      local cmp = require('cmp')
      cmp.setup({
        mapping = cmp.mapping.preset.insert({
          ['<C-Space>'] = cmp.mapping.complete(),
          ['<CR>']      = cmp.mapping.confirm({ select = true }),
          ['<C-e>']     = cmp.mapping.abort(),
          ['<Tab>']     = cmp.mapping.select_next_item(),
          ['<S-Tab>']   = cmp.mapping.select_prev_item(),
        }),
        sources = cmp.config.sources({
          { name = 'nvim_lsp' },
          { name = 'buffer' },
          { name = 'path' },
        }),
      })
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

  -- Format on save
  {
    'stevearc/conform.nvim',
    config = function()
      require('conform').setup({
        formatters_by_ft = {
          python     = { 'ruff_format' },
          typescript = { 'prettier' },
          typescriptreact = { 'prettier' },
          javascript = { 'prettier' },
          rust       = { 'rustfmt' },
        },
        format_on_save = {
          timeout_ms = 500,
          lsp_fallback = true,
        },
      })
    end,
  },

})
