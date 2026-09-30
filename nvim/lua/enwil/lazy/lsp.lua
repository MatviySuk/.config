return {
    "neovim/nvim-lspconfig",
    dependencies = {
        "mason-org/mason.nvim",
        "mason-org/mason-lspconfig.nvim",
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
        local cmp = require("cmp")
        local luasnip = require("luasnip")
        local cmp_lsp = require("cmp_nvim_lsp")

        local capabilities = vim.tbl_deep_extend(
            "force",
            {},
            vim.lsp.protocol.make_client_capabilities(),
            cmp_lsp.default_capabilities()
        )

        require("fidget").setup({})
        require("mason").setup()
        require("guess-indent").setup({})

        -- Defaults shared by every server (nvim 0.11+ native config)
        vim.lsp.config("*", { capabilities = capabilities })

        vim.api.nvim_create_autocmd("LspAttach", {
            group = vim.api.nvim_create_augroup("EnwilLspFormat", {}),
            callback = function(e)
                local client = vim.lsp.get_client_by_id(e.data.client_id)
                if client and client.name ~= "dartls" then -- flutter-tools attaches its own
                    require("lsp-format").on_attach(client, e.buf)
                end
            end,
        })

        vim.lsp.config("lua_ls", {
            settings = {
                Lua = {
                    runtime = { version = "Lua 5.1" },
                    diagnostics = {
                        globals = { "bit", "vim", "it", "describe", "before_each", "after_each" },
                    }
                }
            }
        })

        -- Swift / Objective-C: sourcekit-lsp ships with Xcode, so it is not
        -- managed by Mason. For .xcodeproj/.xcworkspace projects, run
        -- :XcodebuildSetup once so xcode-build-server writes buildServer.json.
        vim.lsp.config("sourcekit", {
            cmd = { "xcrun", "sourcekit-lsp" },
            filetypes = { "swift", "objc", "objcpp" },
            -- xcode-build-server is `#!/usr/bin/env python3`; Homebrew's
            -- python 3.14 can't import plistlib on macOS 26.2 (system libexpat
            -- too old), which silently kills compile flags for .xcodeproj.
            -- Apple's /usr/bin/python3 works, so prefer it for this server.
            cmd_env = { PATH = "/usr/bin:" .. vim.env.PATH },
        })
        vim.lsp.enable("sourcekit")

        -- Kotlin: JetBrains' official server (Mason package "kotlin-lsp").
        -- Android extras (:KotlinSync, library sources) live in enwil.kotlin.
        vim.lsp.config("kotlin_lsp", require("enwil.kotlin").lsp_config())

        -- Python: basedpyright + ruff on the project's virtualenv (enwil.python).
        local basedpyright, ruff = require("enwil.python").lsp_config()
        vim.lsp.config("basedpyright", basedpyright)
        vim.lsp.config("ruff", ruff)

        -- Non-LSP tools Mason should keep installed.
        local registry = require("mason-registry")
        registry.refresh(function()
            for _, name in ipairs({ "debugpy" }) do
                local ok, pkg = pcall(registry.get_package, name)
                if ok and not pkg:is_installed() then pkg:install() end
            end
        end)

        require("mason-lspconfig").setup({
            ensure_installed = {
                "ts_ls",
                "denols",
                "lua_ls",
                "rust_analyzer",
                "marksman",
                "kotlin_lsp",
                "basedpyright",
                "ruff",
                "lemminx", -- Android XML (manifests, layouts, resources)
            },
            -- flutter-tools owns dartls
            automatic_enable = { exclude = { "dartls" } },
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
            window = {
                completion = cmp.config.window.bordered(),
                documentation = cmp.config.window.bordered(),
            },
            formatting = {
                fields = { "abbr", "kind", "menu" },
                format = function(entry, vim_item)
                    -- Swift labels carry the whole signature (argument labels
                    -- and types), so keep more of them visible.
                    if vim.fn.strchars(vim_item.abbr) > 50 then
                        vim_item.abbr = vim.fn.strcharpart(vim_item.abbr, 0, 49) .. "…"
                    end
                    -- Return type / declared type, e.g. "String" for greet(...)
                    local detail = entry.completion_item.detail
                    vim_item.menu = detail and vim.fn.strcharpart(detail, 0, 30) or nil
                    return vim_item
                end,
            },
        })

        for _, method in ipairs({ 'textDocument/diagnostic', 'workspace/diagnostic' }) do
            local default_diagnostic_handler = vim.lsp.handlers[method]
            vim.lsp.handlers[method] = function(err, result, context, config)
                if err ~= nil and err.code == -32802 then
                    return
                end
                return default_diagnostic_handler(err, result, context, config)
            end
        end
    end
}
