return {
    "akinsho/flutter-tools.nvim",
    dependencies = {
        "nvim-lua/plenary.nvim",
        "stevearc/dressing.nvim", -- optional for vim.ui.select
    },
    config = function()
        local capabilities = vim.tbl_deep_extend(
            "force",
            {},
            vim.lsp.protocol.make_client_capabilities(),
            require("cmp_nvim_lsp").default_capabilities()
        )

        require("flutter-tools").setup({
            ui = {
                border = "rounded",
                notification_style = "plugin",
            },
            decorations = {
                statusline = {
                    app_version = true,
                    device = true,
                }
            },
            widget_guides = {
                enabled = true,
            },
            closing_tags = {
                highlight = "Comment",
                prefix = "// ",
                enabled = true,
            },
            dev_log = {
                enabled = true,
                open_cmd = "tabedit",
            },
            outline = {
                open_cmd = "30vnew",
                auto_open = false,
            },
            lsp = {
                on_attach = function(client, bufnr)
                    require("lsp-format").on_attach(client, bufnr)
                    -- Use native color support for Neovim 0.12+
                    if vim.fn.has("nvim-0.12") == 1 and client.server_capabilities.colorProvider then
                        vim.lsp.document_color.enable(true, bufnr)
                    end
                end,
                capabilities = capabilities,
                settings = {
                    showTodos = true,
                    completeFunctionCalls = true,
                    renameFilesWithClasses = "prompt",
                    enableSnippets = true,
                    updateImportsOnRename = true,
                }
            }
        })

        -- Load Telescope extension for Flutter
        pcall(function()
            require("telescope").load_extension("flutter")
        end)
    end
}
