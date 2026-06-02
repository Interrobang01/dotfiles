-- LSP / completion / formatting stack.
--
-- This is the heavy, toolchain-hungry part of the config (mason pulls
-- language servers; pyright and ts_ls need node; treesitter parsers and
-- some servers need a C compiler). It is opt-in per machine via the
-- NVIM_LSP env var (see init.lua). Returns a list of lazy.nvim specs.

return {

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
        dependencies = {
            'williamboman/mason.nvim',
            'neovim/nvim-lspconfig',
            'hrsh7th/cmp-nvim-lsp', -- needed for capabilities below; force load order
        },
        config = function()
            require('mason-lspconfig').setup({
                ensure_installed = {
                    'pyright',       -- Python
                    'ts_ls',         -- TypeScript / JavaScript
                    'rust_analyzer', -- Rust
                    'lua_ls',        -- Lua
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
                    map('gd', vim.lsp.buf.definition, 'Go to definition')
                    map('gD', vim.lsp.buf.declaration, 'Go to declaration')
                    map('gr', vim.lsp.buf.references, 'Find references')
                    map('K', vim.lsp.buf.hover, 'Hover docs')
                    map('<leader>rn', vim.lsp.buf.rename, 'Rename symbol')
                    map('<leader>ca', vim.lsp.buf.code_action, 'Code action')
                    map('<leader>e', vim.diagnostic.open_float, 'Show diagnostic')
                    map('[d', vim.diagnostic.goto_prev, 'Prev diagnostic')
                    map(']d', vim.diagnostic.goto_next, 'Next diagnostic')
                end,
            })
        end,
    },

    -- Autocompletion
    {
        'hrsh7th/nvim-cmp',
        dependencies = {
            'hrsh7th/cmp-nvim-lsp', -- LSP source
            'hrsh7th/cmp-buffer',   -- buffer words
            'hrsh7th/cmp-path',     -- filesystem paths
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

    -- Format on save
    {
        'stevearc/conform.nvim',
        config = function()
            require('conform').setup({
                formatters_by_ft = {
                    python          = { 'ruff_format' },
                    typescript      = { 'prettier' },
                    typescriptreact = { 'prettier' },
                    javascript      = { 'prettier' },
                    rust            = { 'rustfmt' },
                },
                format_on_save = {
                    timeout_ms = 500,
                    lsp_fallback = true,
                },
            })
        end,
    },

}
