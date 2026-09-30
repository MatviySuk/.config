require("enwil.set")
require("enwil.remap")
require("enwil.lazy_init")
require("enwil.android")
require("enwil.ios")
require("enwil.python")

local augroup = vim.api.nvim_create_augroup
local EnwilGroup = augroup('Enwil', {})

local autocmd = vim.api.nvim_create_autocmd
local yank_group = augroup('HighlightYank', {})

function R(name)
    require("plenary.reload").reload_module(name)
end

vim.filetype.add({
    extension = {
        templ = 'templ',
    }
})

autocmd('TextYankPost', {
    group = yank_group,
    pattern = '*',
    callback = function()
        vim.highlight.on_yank({
            higroup = 'IncSearch',
            timeout = 40,
        })
    end,
})

autocmd({ "BufWritePre" }, {
    group = EnwilGroup,
    pattern = "*",
    command = [[%s/\s\+$//e]]
})

autocmd('LspAttach', {
    group = EnwilGroup,
    callback = function(e)
        local opts = { buffer = e.buf }
        local tb = require("telescope.builtin")
        local client = vim.lsp.get_client_by_id(e.data.client_id)

        vim.keymap.set("n", "gd", function() vim.lsp.buf.definition() end, opts)
        vim.keymap.set("n", "gi", tb.lsp_implementations, opts)
        vim.keymap.set("n", "K", function()
            vim.lsp.buf.hover({ max_width = 90, max_height = 30 })
        end, opts)
        vim.keymap.set("n", "<leader>vws", tb.lsp_dynamic_workspace_symbols, opts)
        vim.keymap.set("n", "<leader>vs", tb.lsp_document_symbols, opts)
        vim.keymap.set("n", "<leader>vd", function() vim.diagnostic.open_float() end, opts)
        vim.keymap.set("n", "<leader>vca", function() vim.lsp.buf.code_action() end, opts)
        vim.keymap.set("n", "<leader>vrr", tb.lsp_references, opts)
        vim.keymap.set("n", "<leader>vci", tb.lsp_incoming_calls, opts)
        vim.keymap.set("n", "<leader>vco", tb.lsp_outgoing_calls, opts)
        vim.keymap.set("n", "<leader>vts", function() vim.lsp.buf.typehierarchy("supertypes") end, opts)
        vim.keymap.set("n", "<leader>vtS", function() vim.lsp.buf.typehierarchy("subtypes") end, opts)
        vim.keymap.set("n", "<leader>vrn", function() vim.lsp.buf.rename() end, opts)
        vim.keymap.set("i", "<C-h>", function() vim.lsp.buf.signature_help() end, opts)
        vim.keymap.set("n", "<leader>vi", function()
            vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = e.buf }), { bufnr = e.buf })
        end, opts)
        vim.keymap.set("n", "[d", function() vim.diagnostic.jump({ count = -1, float = true }) end, opts)
        vim.keymap.set("n", "]d", function() vim.diagnostic.jump({ count = 1, float = true }) end, opts)

        -- Swift infers most types, so show them inline (toggle: <leader>vi).
        -- sourcekit registers inlay hints dynamically, hence the name check.
        if client and client.name == "sourcekit" then
            vim.lsp.inlay_hint.enable(true, { bufnr = e.buf })
        end

        -- Highlight other uses of the symbol under the cursor.
        if client and client:supports_method("textDocument/documentHighlight") then
            local hl_group = vim.api.nvim_create_augroup("EnwilLspHighlight" .. e.buf, {})
            autocmd("CursorHold", { group = hl_group, buffer = e.buf, callback = vim.lsp.buf.document_highlight })
            autocmd("CursorMoved", { group = hl_group, buffer = e.buf, callback = vim.lsp.buf.clear_references })
        end
    end
})

vim.g.netrw_browse_split = 0
vim.g.netrw_banner = 0
vim.g.netrw_winsize = 25
