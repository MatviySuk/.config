-- Continue `///` doc comments on <CR>.
vim.opt_local.formatoptions:append("r")

-- Apple documentation for the word under the cursor.
vim.keymap.set("n", "<leader>vD", function()
    vim.ui.open("https://developer.apple.com/search/?q=" .. vim.uri_encode(vim.fn.expand("<cword>")))
end, { buffer = true, desc = "Search Apple docs" })

-- Go-to-definition into UIKit/Foundation/etc. opens sourcekit-lsp's generated
-- interfaces; they are regenerated on demand, so don't edit them.
if vim.api.nvim_buf_get_name(0):find("/GeneratedInterfaces/", 1, true) then
    vim.bo.modifiable = false
    vim.bo.readonly = true
end
