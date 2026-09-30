-- Python: basedpyright (types, navigation, docs) + ruff (lint, format, import
-- sorting), both pointed at the project's virtualenv. For uv projects the
-- virtualenv is created/updated automatically (`uv sync`) when .venv is
-- missing or uv.lock changed, so imports resolve without manual steps.

local M = {}

local cache_dir = vim.fn.stdpath("cache") .. "/python"
vim.fn.mkdir(cache_dir, "p")

local function notify(msg, level) vim.notify("Python: " .. msg, level or vim.log.levels.INFO) end

local root_markers = { "pyproject.toml", "uv.lock", "setup.py", "setup.cfg", "requirements.txt", "Pipfile", "pyrightconfig.json" }

function M.root(path)
    return vim.fs.root(path or 0, root_markers)
end

-- The project's interpreter: an activated env, else .venv/venv in the root.
function M.venv_python(root)
    if vim.env.VIRTUAL_ENV then return vim.env.VIRTUAL_ENV .. "/bin/python" end
    for _, dir in ipairs({ ".venv", "venv" }) do
        local py = root and ("%s/%s/bin/python"):format(root, dir)
        if py and vim.uv.fs_stat(py) then return py end
    end
end

function M.python(root)
    return M.venv_python(root or M.root()) or vim.fn.exepath("python3")
end

local function restart(root)
    for _, c in ipairs(vim.lsp.get_clients()) do
        if (c.name == "basedpyright" or c.name == "ruff") and c.root_dir == root then
            local bufs = vim.tbl_keys(c.attached_buffers)
            local config = c.config
            c:stop()
            vim.defer_fn(function()
                for _, b in ipairs(bufs) do
                    if vim.api.nvim_buf_is_valid(b) then vim.lsp.start(config, { bufnr = b }) end
                end
            end, 500)
        end
    end
end

-- uv projects: keep .venv in sync with uv.lock.
local syncing = {}
local function stamp(root) return cache_dir .. "/" .. root:gsub("/", "%%") .. ".synced" end

function M.ensure_env(root)
    if not root or syncing[root] or vim.fn.executable("uv") == 0 then return end
    local lock = vim.uv.fs_stat(root .. "/uv.lock")
    if not lock then return end
    local st = vim.uv.fs_stat(stamp(root))
    local have_venv = vim.uv.fs_stat(root .. "/.venv/bin/python") ~= nil
    if have_venv and st and st.mtime.sec >= lock.mtime.sec then return end

    syncing[root] = true
    notify(("%s the virtualenv (uv sync)…"):format(have_venv and "updating" or "creating"))
    vim.system({ "uv", "sync" }, { cwd = root, text = true }, vim.schedule_wrap(function(res)
        syncing[root] = nil
        if res.code ~= 0 then
            return notify("uv sync failed:\n" .. (res.stderr or ""):sub(-1200), vim.log.levels.ERROR)
        end
        vim.fn.writefile({}, stamp(root))
        notify("virtualenv ready")
        restart(root)
    end))
end

function M.lsp_config()
    local basedpyright = {
        settings = {
            basedpyright = {
                analysis = {
                    -- "standard" matches pyright's defaults; a project's
                    -- pyrightconfig.json / [tool.pyright] still takes precedence.
                    typeCheckingMode = "standard",
                    autoImportCompletions = true,
                    diagnosticMode = "openFilesOnly",
                },
            },
        },
        on_init = function(client)
            local py = M.venv_python(client.root_dir)
            if py then
                client.settings = vim.tbl_deep_extend("force", client.settings or {}, { python = { pythonPath = py } })
                client:notify("workspace/didChangeConfiguration", { settings = client.settings })
            end
        end,
    }

    local ruff = {
        -- The project's own ruff (pinned in its dev dependencies) so fixes and
        -- formatting match CI; Mason's ruff otherwise.
        cmd = function(dispatchers, config)
            local local_ruff = config.root_dir and config.root_dir .. "/.venv/bin/ruff"
            local exe = local_ruff and vim.uv.fs_stat(local_ruff) and local_ruff or "ruff"
            return vim.lsp.rpc.start({ exe, "server" }, dispatchers, { cwd = config.root_dir })
        end,
        on_attach = function(client)
            client.server_capabilities.hoverProvider = false -- basedpyright's docs win
        end,
    }
    return basedpyright, ruff
end

-- Organize imports (ruff) + format on save; lsp-format already formats with
-- ruff, this adds import sorting in the same step.
local function organize_imports(buf)
    local client = vim.lsp.get_clients({ bufnr = buf, name = "ruff" })[1]
    if not client then return end
    local params = { textDocument = vim.lsp.util.make_text_document_params(buf), range = {
        start = { line = 0, character = 0 }, ["end"] = { line = vim.api.nvim_buf_line_count(buf), character = 0 } },
        context = { only = { "source.organizeImports.ruff" }, diagnostics = {} } }
    local res = client:request_sync("textDocument/codeAction", params, 1000, buf)
    for _, action in ipairs(res and res.result or {}) do
        if not action.edit and action.data then -- ruff sends the edit on resolve
            local resolved = client:request_sync("codeAction/resolve", action, 1000, buf)
            action = resolved and resolved.result or action
        end
        if action.edit then vim.lsp.util.apply_workspace_edit(action.edit, client.offset_encoding) end
    end
end

local group = vim.api.nvim_create_augroup("EnwilPython", {})

vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "python",
    callback = function(ev)
        M.ensure_env(M.root(ev.buf))

        local map = function(lhs, rhs, desc)
            vim.keymap.set("n", lhs, rhs, { buffer = ev.buf, desc = desc })
        end
        local nt = function() return require("neotest") end
        map("<leader>Pt", function() nt().run.run() end, "Python: run nearest test")
        map("<leader>Pf", function() nt().run.run(vim.fn.expand("%")) end, "Python: run tests in file")
        map("<leader>Pa", function() nt().run.run(M.root()) end, "Python: run all tests")
        map("<leader>Pl", function() nt().run.run_last() end, "Python: re-run last test")
        map("<leader>Pd", function() nt().run.run({ strategy = "dap" }) end, "Python: debug nearest test")
        map("<leader>Ps", function() nt().summary.toggle() end, "Python: test summary")
        map("<leader>Po", function() nt().output.open({ enter = true }) end, "Python: test output")
        map("<leader>Pr", function()
            vim.cmd("botright 15split")
            vim.cmd.terminal(vim.fn.shellescape(M.python()) .. " " .. vim.fn.shellescape(vim.fn.expand("#:p")))
        end, "Python: run this file")
        map("<leader>Pv", function() notify("interpreter: " .. M.python()) end, "Python: show interpreter")
        -- Debug this file (the <leader>D… step keys work as usual).
        map("<leader>Dd", function() require("dap").continue() end, "Debug: start (Python)")
    end,
})

vim.api.nvim_create_autocmd("BufWritePre", {
    group = group,
    pattern = "*.py",
    callback = function(ev) organize_imports(ev.buf) end,
})

-- uv.lock changed (e.g. after `uv add` in a terminal): re-sync on focus.
vim.api.nvim_create_autocmd("FocusGained", {
    group = group,
    callback = function()
        if vim.bo.filetype == "python" then M.ensure_env(M.root()) end
    end,
})

return M
