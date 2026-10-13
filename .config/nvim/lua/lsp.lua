-- LSP / completion / formatting stack.
--
-- This is the heavy, toolchain-hungry part of the config (mason pulls
-- language servers; pyright and ts_ls need node; treesitter parsers and
-- some servers need a C compiler). It is opt-in per machine via the
-- NVIM_LSP env var (see init.lua). Returns a list of lazy.nvim specs.

local server_list = {
    'pyright',       -- Python
    'ts_ls',         -- TypeScript / JavaScript
    'rust_analyzer', -- Rust
    'lua_ls',        -- Lua
    'clangd',        -- C++
}

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
                ensure_installed = server_list,
                automatic_installation = true,
            })

            local capabilities = require('cmp_nvim_lsp').default_capabilities()

            -- Configure each server using nvim 0.11+ native API
            for _, server in ipairs(server_list) do
                vim.lsp.config(server, { capabilities = capabilities })
            end
            vim.lsp.enable(server_list)

            -- clangd looks for compile_commands.json only in each ancestor
            -- directory and its build/, but Qt Creator (and multi-config
            -- setups generally) configure into build/<kit>-<config>/. Rather
            -- than symlinking per project, find it here: walk up from the
            -- file, and at the first project that has no database where
            -- clangd would look but does have build/*/compile_commands.json,
            -- point clangd at the newest one -- i.e. the configuration most
            -- recently (re)configured. Where clangd would find its own, stay
            -- out of the way.
            local function compdb_dir(file)
                for dir in vim.fs.parents(file) do
                    if vim.uv.fs_stat(dir .. '/compile_commands.json')
                        or vim.uv.fs_stat(dir .. '/build/compile_commands.json') then
                        return nil
                    end
                    local best, best_mtime
                    for _, f in ipairs(vim.fn.glob(dir .. '/build/*/compile_commands.json', false, true)) do
                        local mtime = vim.uv.fs_stat(f).mtime.sec
                        if not best_mtime or mtime > best_mtime then best, best_mtime = f, mtime end
                    end
                    if best then return vim.fs.dirname(best) end
                end
            end

            vim.lsp.config('clangd', {
                -- A function cmd runs at each server start, so a freshly
                -- configured build dir is picked up by :lsp restart. The
                -- current buffer is the one whose FileType started it.
                cmd = function(dispatchers, config)
                    local cmd = { 'clangd' }
                    local dir = compdb_dir(vim.api.nvim_buf_get_name(0))
                    if dir then table.insert(cmd, '--compile-commands-dir=' .. dir) end
                    return vim.lsp.rpc.start(cmd, dispatchers, {
                        cwd = config.cmd_cwd, env = config.cmd_env, detached = config.detached,
                    })
                end,
            })

            -- Servers from the system package manager rather than mason, so
            -- not in server_list (mason would download a second copy).
            -- tinymist: Typst. formatterMode turns on its built-in typstyle,
            -- which conform's LSP fallback then runs on save.
            vim.lsp.config('tinymist', {
                capabilities = capabilities,
                settings = { formatterMode = 'typstyle' },
            })
            if vim.fn.executable('tinymist') == 1 then
                vim.lsp.enable('tinymist')
            end

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
            'hrsh7th/cmp-nvim-lsp',  -- LSP source
            'hrsh7th/cmp-buffer',    -- buffer words
            'hrsh7th/cmp-path',      -- filesystem paths
            'windwp/nvim-autopairs', -- auto pair delimiters on function accept
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
            cmp.event:on('confirm_done', require('nvim-autopairs.completion.cmp').on_confirm_done())
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
                    c               = { 'clang_format' },
                    cpp             = { 'clang_format' },
                },
                format_on_save = {
                    timeout_ms = 500,
                    lsp_format = 'fallback',
                },
            })
        end,
    },

}
