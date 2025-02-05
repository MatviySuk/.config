return {
    "neovim/nvim-lspconfig",
    dependencies = {
        "williamboman/mason.nvim",
        "williamboman/mason-lspconfig.nvim",
        "lukas-reineke/lsp-format.nvim",
        "nmac427/guess-indent.nvim",
        "hrsh7th/cmp-nvim-lsp",
        "hrsh7th/cmp-buffer",
        "hrsh7th/cmp-path",
        "hrsh7th/cmp-cmdline",
        {
            "hrsh7th/nvim-cmp",
            version = false,
            event = "InsertEnter",
            dependencies = {
                "hrsh7th/cmp-nvim-lsp",
                "hrsh7th/cmp-path",
                "hrsh7th/cmp-buffer",
                "L3MON4D3/LuaSnip",
            },
        },
        "L3MON4D3/LuaSnip",
        "saadparwaiz1/cmp_luasnip",
        "j-hui/fidget.nvim",
    },

    config = function()
        local lspconfig = require("lspconfig")
        local cmp = require("cmp")
        local luasnip = require("luasnip")
        local cmp_lsp = require("cmp_nvim_lsp")

        local capabilities = vim.tbl_deep_extend(
            "force",
            {},
            vim.lsp.protocol.make_client_capabilities(),
            cmp_lsp.default_capabilities()
        )

        local default_on_attach = function(client, bufnr)
            require("lsp-format").on_attach(client, bufnr)
        end

        require("fidget").setup({})
        require("mason").setup()
        require("guess-indent").setup({})
        require("mason-lspconfig").setup({
            ensure_installed = {
                "ts_ls",
                "denols",
                "lua_ls",
                "rust_analyzer",
            },
            handlers = {
                function(server_name)
                    if server_name == "lua_ls" then
                        lspconfig.lua_ls.setup({
                            capabilities = capabilities,
                            on_attach = default_on_attach,
                            settings = {
                                Lua = {
                                    runtime = { version = "Lua 5.1" },
                                    diagnostics = {
                                        globals = { "bit", "vim", "it", "describe", "before_each", "after_each" },
                                    }
                                }
                            }
                        })
                    elseif server_name == "sourcekit" then
                        lspconfig.sourcekit.setup({
                            cmd = { "xcrun", "sourcekit-lsp" },
                            filetypes = { "swift" },
                            root_dir = lspconfig.util.root_pattern("Package.swift", ".git"),
                            capabilities = capabilities,
                            on_attach = default_on_attach,
                        })
                    elseif server_name == "rust_analyzer" then
                        lspconfig.rust_analyzer.setup({
                            capabilities = capabilities,
                            on_attach = function(client, bufnr)
                                default_on_attach(client, bufnr)

                                -- client.server_capabilities.completionProvider = true
                            end,
                        })
                    elseif server_name == "ts_ls" then
                        lspconfig.ts_ls.setup({
                            capabilities = capabilities,
                            on_attach = default_on_attach,
                        })
                    else
                        lspconfig[server_name].setup({
                            capabilities = capabilities,
                            on_attach = default_on_attach,
                        })
                    end
                end
            }
        })

        vim.diagnostic.config({
            virtual_text = true,
            signs = true,
            underline = true,
            update_in_insert = false,
            severity_sort = true,
            float = {
                focusable = true,
                style = "minimal",
                border = "rounded",
                source = "always",
                header = "",
                prefix = "",
            },
        })

        cmp.setup({
            snippet = {
                expand = function(args)
                    luasnip.lsp_expand(args.body) -- Use luasnip correctly
                end,
            },
            mapping = cmp.mapping.preset.insert({
                ['<C-y>'] = cmp.mapping.confirm({ select = true }),
                ['<C-n>'] = cmp.mapping.select_next_item({ behavior = cmp.SelectBehavior.Select }),
                ['<C-p>'] = cmp.mapping.select_prev_item({ behavior = cmp.SelectBehavior.Select }),
                ["<C-Space>"] = cmp.mapping.complete(),
            }),
            sources = cmp.config.sources({
                { name = "nvim_lsp" },
                { name = "luasnip" },
                { name = "buffer" },
                { name = "path" },
            }),
            formatting = {
                fields = { "abbr", "kind", "menu" },
                format = function(_, vim_item)
                    vim_item.abbr = string.sub(vim_item.abbr, 1, 30)
                    return vim_item
                end,
            },
        })
    end
}
