-- Debugging. Swift/iOS uses Xcode's own `xcrun lldb-dap` via xcodebuild.nvim
-- (Xcode 16+, no codelldb needed).
return {
    "mfussenegger/nvim-dap",
    dependencies = {
        "rcarriga/nvim-dap-ui",
        "nvim-neotest/nvim-nio",
        "wojciech-kulik/xcodebuild.nvim",
    },
    config = function()
        local dap = require("dap")
        local dapui = require("dapui")
        local xcodebuild = require("xcodebuild.integrations.dap")

        xcodebuild.setup()

        dapui.setup({
            layouts = {
                {
                    elements = { "scopes", "breakpoints", "stacks", "watches" },
                    size = 50,
                    position = "left",
                },
                {
                    -- console shows the app's stdout / simulator logs
                    elements = { "repl", "console" },
                    size = 0.3,
                    position = "bottom",
                },
            },
        })

        dap.listeners.after.event_initialized["dapui_config"] = function() dapui.open() end
        dap.listeners.before.event_terminated["dapui_config"] = function() dapui.close() end
        dap.listeners.before.event_exited["dapui_config"] = function() dapui.close() end

        local map = function(lhs, rhs, desc)
            vim.keymap.set("n", lhs, rhs, { desc = desc })
        end

        map("<leader>b", xcodebuild.toggle_breakpoint, "Debug: toggle breakpoint")
        map("<leader>B", xcodebuild.toggle_message_breakpoint, "Debug: log breakpoint")
        map("<leader>Dd", xcodebuild.build_and_debug, "Debug: build & debug (iOS)")
        map("<leader>Dr", xcodebuild.debug_without_build, "Debug: debug without build (iOS)")
        map("<leader>Dt", xcodebuild.debug_tests, "Debug: tests (iOS)")
        map("<leader>DT", xcodebuild.debug_class_tests, "Debug: class tests (iOS)")
        map("<leader>Dx", xcodebuild.terminate_session, "Debug: terminate")
        map("<leader>Dc", dap.continue, "Debug: continue")
        map("<leader>Dn", dap.step_over, "Debug: step over")
        map("<leader>Di", dap.step_into, "Debug: step into")
        map("<leader>Do", dap.step_out, "Debug: step out")
        map("<leader>Du", dapui.toggle, "Debug: toggle UI")
        vim.keymap.set({ "n", "v" }, "<leader>De", dapui.eval, { desc = "Debug: eval" })
    end,
}
