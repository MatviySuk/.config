-- iOS / macOS development: build, run, test, simulators, devices, previews,
-- coverage and debugging from Neovim. External tools (see README section
-- "Requirements" or run `make install` in the plugin dir):
--   brew install xcode-build-server xcbeautify xcp pipx jq coreutils
--   pipx install pymobiledevice3     -- physical devices
--   gem install xcodeproj            -- adding/removing files in .xcodeproj
return {
    {
        "wojciech-kulik/xcodebuild.nvim",
        dependencies = {
            "nvim-telescope/telescope.nvim",
            "MunifTanjim/nui.nvim",
            "folke/snacks.nvim",
        },
        config = function()
            require("xcodebuild").setup({
                code_coverage = { enabled = true },
                logs = {
                    auto_open_on_failed_build = true,
                    auto_close_on_app_launch = true,
                },
            })

            local map = function(lhs, rhs, desc)
                vim.keymap.set("n", lhs, rhs, { desc = desc })
            end

            map("<leader>XX", "<cmd>XcodebuildPicker<cr>", "Xcode: all actions")
            map("<leader>Xs", "<cmd>XcodebuildSetup<cr>", "Xcode: project setup")
            map("<leader>Xb", "<cmd>XcodebuildBuild<cr>", "Xcode: build")
            map("<leader>XB", "<cmd>XcodebuildBuildForTesting<cr>", "Xcode: build for testing")
            map("<leader>Xr", "<cmd>XcodebuildBuildRun<cr>", "Xcode: build & run")
            map("<leader>XR", "<cmd>XcodebuildRun<cr>", "Xcode: run without build")
            map("<leader>Xc", "<cmd>XcodebuildCancel<cr>", "Xcode: cancel")
            map("<leader>Xd", "<cmd>XcodebuildSelectDevice<cr>", "Xcode: select device")
            map("<leader>XS", "<cmd>XcodebuildSelectScheme<cr>", "Xcode: select scheme")
            map("<leader>Xl", "<cmd>XcodebuildToggleLogs<cr>", "Xcode: toggle logs")
            map("<leader>Xt", "<cmd>XcodebuildTest<cr>", "Xcode: test all")
            map("<leader>XT", "<cmd>XcodebuildTestClass<cr>", "Xcode: test class")
            map("<leader>Xn", "<cmd>XcodebuildTestNearest<cr>", "Xcode: test nearest")
            map("<leader>Xf", "<cmd>XcodebuildTestFailing<cr>", "Xcode: rerun failing tests")
            map("<leader>Xe", "<cmd>XcodebuildTestExplorerToggle<cr>", "Xcode: test explorer")
            map("<leader>Xv", "<cmd>XcodebuildToggleCodeCoverage<cr>", "Xcode: toggle coverage")
            map("<leader>XV", "<cmd>XcodebuildShowCodeCoverageReport<cr>", "Xcode: coverage report")
            map("<leader>Xp", "<cmd>XcodebuildPreviewGenerateAndShow<cr>", "Xcode: SwiftUI preview")
            map("<leader>XP", "<cmd>XcodebuildPreviewToggle<cr>", "Xcode: toggle preview")
            map("<leader>Xa", "<cmd>XcodebuildCodeActions<cr>", "Xcode: code actions")
            map("<leader>Xq", "<cmd>Telescope quickfix<cr>", "Xcode: build errors")
            map("<leader>Xo", "<cmd>XcodebuildOpenInXcode<cr>", "Xcode: open in Xcode")
        end,
    },
    {
        -- Only the image module, used by xcodebuild.nvim for SwiftUI/UIKit
        -- previews (Ghostty/Kitty graphics protocol).
        "folke/snacks.nvim",
        lazy = true,
        opts = { image = { enabled = true } },
    },
}
