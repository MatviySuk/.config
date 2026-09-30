-- Kotlin / Android support around JetBrains' kotlin-lsp.
--
-- Plain Kotlin/JVM Gradle projects work out of the box. Android projects on
-- AGP 8 need help, because kotlin-lsp's own Gradle import leaves out every
-- AAR library (AndroidX, Compose, Material...) and often fails outright:
--   * an import-only Gradle init script (gradle/kotlin-lsp-import.gradle)
--     makes the import succeed;
--   * after every successful import of an Android project, the exported
--     model is extended with the AAR class jars and -sources.jars resolved by
--     Gradle and saved as workspace.json, which kotlin-lsp then loads instead
--     of importing Gradle itself. This happens automatically: on first open,
--     when a build file is saved, and when a build file changed since the
--     last sync. :KotlinSync forces it.
-- Library sources / compiled classes come back as jar:/jrt: URIs, which are
-- opened read-only below (with the LSP attached, so navigation continues).

local M = {}

local config_dir = vim.fn.stdpath("config") .. "/gradle"
local cache_dir = vim.fn.stdpath("cache") .. "/kotlin-lsp"
vim.fn.mkdir(cache_dir, "p")

-- kotlin-lsp deletes the init scripts it is given once an import finishes,
-- so it only ever gets this copy, refreshed before every (re)import.
local import_script = ("%s/import-%d.gradle"):format(cache_dir, vim.fn.getpid())
local function refresh_import_script()
    vim.uv.fs_copyfile(config_dir .. "/kotlin-lsp-import.gradle", import_script)
end
refresh_import_script()
vim.api.nvim_create_autocmd("VimLeavePre", { callback = function() os.remove(import_script) end })

local function is_android(root)
    return vim.fn.glob(root .. "/*/src/main/AndroidManifest.xml") ~= ""
        or vim.fn.glob(root .. "/*/*/src/main/AndroidManifest.xml") ~= ""
end

local function workspace_json(root) return root .. "/workspace.json" end

-- Roots whose workspace.json was written by :KotlinSync (so it is safe to
-- regenerate); stamps live outside the project.
local function stamp(root) return cache_dir .. "/" .. root:gsub("[/\\:]", "%%") .. ".synced" end

local import_waiters = {} -- client id -> callback(state)
local exit_waiters = {}   -- client id -> callback()
local import_logs = {}    -- client id -> recent Gradle output of its import
local syncing = {}        -- root -> true while a sync runs, "again" if re-requested

local function notify(msg, level) vim.notify("KotlinSync: " .. msg, level or vim.log.levels.INFO) end

local function on_import_log(_, params, ctx)
    local log = import_logs[ctx.client_id] or {}
    table.insert(log, params.message or "")
    if #log > 2000 then table.remove(log, 1) end
    import_logs[ctx.client_id] = log
end

-- The useful part of a failed Gradle import: what follows "What went wrong:".
local function import_failure(client_id, fallback)
    local lines = vim.split(table.concat(import_logs[client_id] or {}), "\n", { trimempty = true })
    local reason = {}
    for i, line in ipairs(lines) do
        if line:find("What went wrong:", 1, true) then
            reason = {}
            for j = i + 1, math.min(i + 4, #lines) do
                if lines[j]:match("^%* ") then break end
                table.insert(reason, vim.trim(lines[j]))
            end
        end
    end
    return #reason > 0 and table.concat(reason, "\n") or fallback or "unknown error"
end

local finish -- defined below; completes a sync after a successful import

local function on_import_state(_, state, ctx)
    if not state or state.phase ~= "FINISHED" then return end
    refresh_import_script()
    local waiter = import_waiters[ctx.client_id]
    if waiter then
        import_waiters[ctx.client_id] = nil
        return waiter(state)
    end
    local client = vim.lsp.get_client_by_id(ctx.client_id)
    local root = client and client.root_dir
    for _, folder in ipairs(state.folders or {}) do
        if folder.status == "FAILED" then
            notify(("%s import failed:\n%s"):format(folder.tool or "project",
                import_failure(ctx.client_id, folder.message)), vim.log.levels.ERROR)
        elseif root and folder.tool == "gradle" and is_android(root) and not syncing[root] then
            -- Fresh Gradle import of an Android project: add the libraries.
            syncing[root] = true
            finish(client, root)
        end
    end
end

-- Build files whose change means the saved workspace.json is out of date.
local function build_files(root)
    local files = {}
    for _, pattern in ipairs({ "settings.gradle*", "build.gradle*", "*/build.gradle*", "*/*/build.gradle*",
        "gradle/libs.versions.toml", "gradle.properties" }) do
        vim.list_extend(files, vim.fn.glob(root .. "/" .. pattern, false, true))
    end
    return files
end

local function is_stale(root)
    local ws = vim.uv.fs_stat(workspace_json(root))
    if not ws then return false end
    for _, f in ipairs(build_files(root)) do
        local st = vim.uv.fs_stat(f)
        if st and st.mtime.sec > ws.mtime.sec then return true end
    end
    return false
end

function M.lsp_config()
    return {
        -- Groups in priority order: the settings file marks the root of a
        -- multi-module build, even when a module's build file is nearer.
        root_markers = {
            { "workspace.json", "settings.gradle.kts", "settings.gradle" },
            { "build.gradle.kts", "build.gradle", "pom.xml" },
        },
        cmd_env = {
            IJ_JAVA_OPTIONS = "-Dcom.jetbrains.ls.imports.gradle.init.scripts=" .. import_script,
        },
        before_init = function(params, config)
            refresh_import_script()
            local root = config.root_dir
            if root and vim.uv.fs_stat(stamp(root)) and is_stale(root) then
                -- Build changed since the last sync: re-import (and re-sync).
                os.remove(workspace_json(root))
            end
            if root and vim.uv.fs_stat(workspace_json(root)) then
                -- Load workspace.json instead of re-importing Gradle.
                params.initializationOptions = vim.tbl_extend("force", params.initializationOptions or {}, {
                    projects = { { type = "json", path = vim.uri_from_fname(root) } },
                })
            end
        end,
        handlers = {
            ["intellij/workspaceImportState"] = on_import_state,
            ["intellij/importLog"] = on_import_log,
        },
        on_exit = function(_, _, client_id)
            local waiter = exit_waiters[client_id]
            exit_waiters[client_id] = nil
            import_logs[client_id] = nil
            if waiter then waiter() end
        end,
    }
end

-- Sync ------------------------------------------------------------------------

local function kotlin_buffers(root)
    return vim.tbl_filter(function(b)
        return vim.api.nvim_buf_is_loaded(b) and vim.bo[b].filetype == "kotlin"
            and vim.startswith(vim.api.nvim_buf_get_name(b), root .. "/")
    end, vim.api.nvim_list_bufs())
end

-- Stops the project's kotlin_lsp clients and calls on_stopped once their
-- processes have exited: a new server can't open the project index while the
-- old JVM still holds its lock.
local function stop_clients(root, on_stopped)
    local pending = 0
    for _, c in ipairs(vim.lsp.get_clients({ name = "kotlin_lsp" })) do
        if c.root_dir == root then
            pending = pending + 1
            exit_waiters[c.id] = function()
                pending = pending - 1
                if pending == 0 then vim.schedule(on_stopped) end
            end
            c:stop()
            vim.defer_fn(function() if not c:is_stopped() then c:stop(true) end end, 15000)
        end
    end
    if pending == 0 then vim.schedule(on_stopped) end
end

local function start_client(root, bufs)
    local config = vim.tbl_extend("force", vim.lsp.config.kotlin_lsp, { name = "kotlin_lsp", root_dir = root })
    local id
    for _, b in ipairs(bufs) do id = vim.lsp.start(config, { bufnr = b }) end
    return id and vim.lsp.get_client_by_id(id)
end

-- Adds AAR libraries, sources jars and inter-module dependencies reported by
-- the lspClasspath Gradle task to the workspace kotlin-lsp exported.
local function merge(ws, projects, root, sdk_root)
    local libs, modules = {}, {}
    for _, lib in ipairs(ws.libraries) do libs[lib.name] = lib end
    for _, m in ipairs(ws.modules) do modules[#modules + 1] = m end

    local function find_module(project_path, variant)
        for _, m in ipairs(modules) do
            if m.externalProjectId == project_path and vim.endswith(m.name, "." .. variant) then return m end
        end
    end

    local function add_dep(m, dep)
        for _, d in ipairs(m.dependencies) do
            if d.type == dep.type and d.name == dep.name then return end
        end
        table.insert(m.dependencies, dep)
    end

    local function add_sources(lib, path)
        for _, r in ipairs(lib.roots) do
            if r.type == "SOURCES" then return end
        end
        table.insert(lib.roots, { path = path, type = "SOURCES" })
    end

    local added = 0
    for _, p in ipairs(projects) do
        for variant, artifacts in pairs(p.variants) do
            local m = find_module(p.project, variant)
            if m then
                for _, a in ipairs(artifacts) do
                    if a.project then
                        local main = variant:gsub("UnitTest$", "")
                        local dep = find_module(a.project, main) or find_module(a.project, "debug")
                        if dep and dep ~= m then
                            add_dep(m, { type = "module", name = dep.name, scope = "compile" })
                        end
                    else
                        local name = "Gradle: " .. a.id
                        local lib = libs[name]
                        if not lib then
                            lib = { name = name, type = "COMPILE", roots = { { path = a.classes } } }
                            libs[name] = lib
                            table.insert(ws.libraries, lib)
                            added = added + 1
                        end
                        if a.sources then add_sources(lib, a.sources) end
                        add_dep(m, { type = "library", name = name, scope = "compile" })
                    end
                end
            end
        end
    end

    -- Drop roots that don't exist (e.g. the app's own classes.jar before the
    -- first build); kotlin-lsp warns about each of them on every start.
    local function expand(path)
        return (path:gsub("^<WORKSPACE>", root):gsub("^<HOME>", vim.env.HOME))
    end
    for _, lib in ipairs(ws.libraries) do
        lib.roots = vim.tbl_filter(function(r) return vim.uv.fs_stat(expand(r.path)) ~= nil end, lib.roots)
    end

    -- Android SDK sources (sdkmanager "sources;android-XX") for android.jar docs.
    for _, lib in ipairs(ws.libraries) do
        if lib.name:find("android:android%-sdk") and lib.roots[1] then
            local api = lib.roots[1].path:match("platforms/(android%-[%w.]+)/android%.jar")
            local src = api and sdk_root .. "/sources/" .. api
            if src and vim.fn.isdirectory(src) == 1 then add_sources(lib, src) end
        end
    end

    local with_sources = 0
    for _, lib in ipairs(ws.libraries) do
        for _, r in ipairs(lib.roots) do
            if r.type == "SOURCES" then with_sources = with_sources + 1; break end
        end
    end
    return added, with_sources, #ws.libraries
end

local function done(root)
    local again = syncing[root] == "again"
    syncing[root] = nil
    if again then M.sync(root) end
end

-- Steps after a successful Gradle import by `client`: export kotlin-lsp's model
-- (modules, source roots, compiler plugins), add every library Gradle resolves
-- (AARs included) with sources, save it as workspace.json and restart on it.
finish = function(client, root)
    local ws_file = workspace_json(root)
    notify("loading Android libraries and sources…")
    client:request("workspace/executeCommand", { command = "exportWorkspace", arguments = { root } }, function(err)
        if err or not vim.uv.fs_stat(ws_file) then
            notify("exportWorkspace failed: " .. vim.inspect(err), vim.log.levels.ERROR)
            return done(root)
        end
        -- lspClasspath reads the project model at execution time, which the
        -- configuration cache (enabled by many projects) doesn't allow.
        vim.system({ "./gradlew", "--console=plain", "-q", "--no-configuration-cache",
                "-I", config_dir .. "/kotlin-lsp-classpath.gradle", "lspClasspath" },
            { cwd = root, text = true }, vim.schedule_wrap(function(res)
                if res.code ~= 0 then
                    os.remove(ws_file)
                    notify("resolving libraries failed:\n" .. (res.stderr or ""):sub(-1500), vim.log.levels.ERROR)
                    return done(root)
                end
                local projects = {}
                for line in res.stdout:gmatch("[^\n]+") do
                    local json = line:match("^LSPJSON (.*)")
                    if json then table.insert(projects, vim.json.decode(json)) end
                end

                local ws = vim.json.decode(table.concat(vim.fn.readfile(ws_file), "\n"))
                local _, with_sources, total = merge(ws, projects, root,
                    vim.env.ANDROID_HOME or vim.fn.expand("~/Library/Android/sdk"))
                vim.fn.writefile({ vim.json.encode(ws) }, ws_file)
                vim.fn.writefile({}, stamp(root))
                require("enwil.util").exclude_from_git(ws_file)

                stop_clients(root, function()
                    start_client(root, kotlin_buffers(root))
                    notify(("ready: %d libraries, %d with sources/docs"):format(total, with_sources))
                    done(root)
                end)
            end))
    end)
end

-- Fresh Gradle import followed by finish(). Used by :KotlinSync and when a
-- build file is saved.
function M.sync(root)
    root = root or vim.fs.root(0, { "settings.gradle.kts", "settings.gradle" })
        or vim.fs.root(0, { "build.gradle.kts", "build.gradle" })
    if not root then return notify("no Gradle project above this buffer", vim.log.levels.ERROR) end
    if syncing[root] then
        syncing[root] = "again"
        return
    end
    local ws_file = workspace_json(root)
    if vim.uv.fs_stat(ws_file) and not vim.uv.fs_stat(stamp(root)) then
        return notify(ws_file .. " was not generated by :KotlinSync; not overwriting it", vim.log.levels.ERROR)
    end

    os.remove(ws_file)
    local bufs = kotlin_buffers(root)
    if #bufs == 0 then return end -- next open of a Kotlin file imports and syncs

    syncing[root] = true
    notify("importing Gradle project…")
    stop_clients(root, function()
        local client = start_client(root, bufs)
        if not client then
            notify("could not start kotlin_lsp", vim.log.levels.ERROR)
            return done(root)
        end
        import_waiters[client.id] = function(state)
            local folder = state.folders and state.folders[1]
            if folder and folder.status == "FAILED" then
                notify("Gradle import failed:\n" .. import_failure(client.id, folder.message), vim.log.levels.ERROR)
                return done(root)
            end
            finish(client, root)
        end
    end)
end

-- Re-sync when a build file of a synced project is saved.
vim.api.nvim_create_autocmd("BufWritePost", {
    group = vim.api.nvim_create_augroup("EnwilKotlinSync", {}),
    pattern = { "*.gradle.kts", "*.gradle", "libs.versions.toml", "gradle.properties" },
    callback = function(ev)
        local root = vim.fs.root(ev.buf, { "settings.gradle.kts", "settings.gradle" })
        if root and vim.uv.fs_stat(stamp(root)) then M.sync(root) end
    end,
})

-- jar: / jrt: buffers ------------------------------------------------------

local function kotlin_client()
    local clients = vim.lsp.get_clients({ name = "kotlin_lsp" })
    return clients[#clients]
end

local function read_library_file(ev)
    local buf, uri = ev.buf, ev.match
    local jar, entry = uri:match("^jar:/*(/.-)!/(.+)$")
    local lines, ft

    if jar and not entry:match("%.class$") then
        local res = vim.system({ "unzip", "-p", jar, entry }, { text = true }):wait()
        lines = vim.split(res.stdout or "", "\n")
        ft = vim.filetype.match({ filename = entry })
    else
        -- Compiled class (no sources available): let kotlin-lsp decompile it.
        local client = kotlin_client()
        local res = client and client:request_sync("workspace/executeCommand",
            { command = "decompile", arguments = { uri } }, 20000, buf)
        local out = res and res.result
        if not out or not out.code then
            lines = { "// Could not open " .. uri, "// " .. vim.inspect(res and res.err or "no kotlin_lsp client") }
        else
            lines = vim.split(out.code, "\n")
            ft = (out.language or "java"):lower()
        end
    end

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].buftype = "nowrite"
    vim.bo[buf].swapfile = false
    vim.bo[buf].modifiable = false
    vim.bo[buf].readonly = true
    vim.bo[buf].modified = false
    if ft then vim.bo[buf].filetype = ft end

    -- Keep go-to-definition / hover working inside library sources.
    local client = kotlin_client()
    if client then vim.lsp.buf_attach_client(buf, client.id) end
end

vim.api.nvim_create_autocmd("BufReadCmd", {
    group = vim.api.nvim_create_augroup("EnwilKotlinJar", {}),
    pattern = { "jar:/*", "jrt:/*" }, -- a "/" makes Vim match the full URI, not the tail
    callback = read_library_file,
})

vim.api.nvim_create_user_command("KotlinSync", function() M.sync() end, {
    desc = "Re-import the Gradle project and reload all Android libraries into kotlin-lsp",
})

return M
