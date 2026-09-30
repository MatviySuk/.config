-- Python debugging (debugpy via Mason) and tests (pytest via neotest).
-- LSP, venv handling and keymaps live in lua/enwil/python.lua.
return {
    {
        "mfussenegger/nvim-dap-python",
        ft = "python",
        dependencies = { "mfussenegger/nvim-dap" },
        config = function()
            local debugpy = vim.fn.stdpath("data") .. "/mason/packages/debugpy/venv/bin/python"
            local dap_python = require("dap-python")
            dap_python.setup(debugpy)
            dap_python.test_runner = "pytest"
            -- Debug the program with the project's interpreter, not debugpy's.
            dap_python.resolve_python = function() return require("enwil.python").python() end
        end,
    },
    {
        "nvim-neotest/neotest",
        ft = "python",
        dependencies = {
            "nvim-neotest/nvim-nio",
            "nvim-lua/plenary.nvim",
            "nvim-treesitter/nvim-treesitter",
            "nvim-neotest/neotest-python",
            "mfussenegger/nvim-dap-python",
        },
        config = function()
            require("neotest").setup({
                adapters = {
                    require("neotest-python")({
                        runner = "pytest",
                        python = function() return require("enwil.python").python() end,
                        dap = { justMyCode = false },
                    }),
                },
            })
        end,
    },
}
