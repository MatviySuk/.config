return {
    "nvim-treesitter/nvim-treesitter",
    branch = "main", -- Required for Neovim 0.12+
    lazy = false,
    build = ":TSUpdate",
    config = function()
        require('nvim-treesitter').setup()

        local langs = {
            "vimdoc", "javascript", "typescript", "c", "lua", "rust",
            "jsdoc", "bash", "dart", "markdown", "markdown_inline", "templ",
            -- iOS / Android
            "swift", "objc", "kotlin", "java", "groovy", "xml", "json",
            "yaml", "toml",
        }

        -- Only attempt to install if the CLI is available
        if vim.fn.executable('tree-sitter') == 1 then
            require('nvim-treesitter').install(langs)
        end

        vim.api.nvim_create_autocmd('FileType', {
            callback = function(args)
                local lang = vim.bo[args.buf].filetype
                if vim.tbl_contains(langs, lang) then
                    pcall(vim.treesitter.start)
                end
            end,
        })
    end
}

