return {
    "ThePrimeagen/harpoon",
    branch = "harpoon2",
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
        local harpoon = require("harpoon")

        harpoon:setup()

        vim.keymap.set("n", "<leader>a", function() harpoon:list():add() end)
        vim.keymap.set("n", "<leader>o", function() harpoon.ui:toggle_quick_menu(harpoon:list()) end)

        vim.keymap.set("n", "<leader>m", function() harpoon:list():select(1) end)
        vim.keymap.set("n", "<leader>n", function() harpoon:list():select(2) end)
        vim.keymap.set("n", "<leader>e", function() harpoon:list():select(3) end)
        vim.keymap.set("n", "<leader>i", function() harpoon:list():select(4) end)
        vim.keymap.set("n", "<leader><C-m>", function() harpoon:list():replace_at(1) end)
        vim.keymap.set("n", "<leader><C-n>", function() harpoon:list():replace_at(2) end)
        vim.keymap.set("n", "<leader><C-e>", function() harpoon:list():replace_at(3) end)
        vim.keymap.set("n", "<leader><C-i>", function() harpoon:list():replace_at(4) end)
    end
}
