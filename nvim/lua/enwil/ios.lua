-- Keeps Xcode projects ready for sourcekit-lsp without manual steps.
--
-- sourcekit-lsp only understands .xcodeproj/.xcworkspace projects through
-- xcode-build-server, which reads compiler flags from the latest Xcode build
-- log. So when a Swift file of an Xcode project is opened:
--   1. buildServer.json is created (scheme picked automatically) and
--      sourcekit restarted on the project root;
--   2. xcodebuild.nvim is configured (scheme + a simulator) if it isn't yet,
--      so <leader>X… commands work without :XcodebuildSetup;
--   3. a background build runs when there is no build yet or the project
--      files changed since the last one. xcode-build-server notices the new
--      log and updates sourcekit by itself.
-- Generated files (buildServer.json, .nvim/) are hidden from git locally.
-- Swift packages (Package.swift only) need none of this.

local util = require("enwil.util")

local M = {}

local log_dir = vim.fn.stdpath("cache") .. "/ios"
vim.fn.mkdir(log_dir, "p")

local state = {} -- root -> { busy, checked_at, project, scheme, pbxprojs }

local function notify(msg, level) vim.notify("Xcode: " .. msg, level or vim.log.levels.INFO) end

local function is_container(name, ext)
    return name:match("%." .. ext .. "$") ~= nil
end

-- Project root: where buildServer.json lives, else the top-most directory
-- holding an .xcworkspace (inside the git repo), else the nearest .xcodeproj.
local function find_root(path)
    local configured = vim.fs.root(path, "buildServer.json")
    if configured then return configured end
    local top = vim.fs.root(path, ".git")
    local best
    for dir in vim.fs.parents(path) do
        for name in vim.fs.dir(dir) do
            if is_container(name, "xcworkspace") then best = dir end
        end
        if dir == top then break end
    end
    return best or vim.fs.root(path, function(name) return is_container(name, "xcodeproj") end)
end

local function project_file(root)
    local workspace, project
    for name in vim.fs.dir(root) do
        if is_container(name, "xcworkspace") then workspace = workspace or name end
        if is_container(name, "xcodeproj") then project = project or name end
    end
    local name = workspace or project
    return name and root .. "/" .. name, workspace and "-workspace" or "-project"
end

local function build_server(root)
    local path = root .. "/buildServer.json"
    if not vim.uv.fs_stat(path) then return nil end
    local ok, json = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
    return ok and json or nil
end

-- Scheme named after the project, else the first one that isn't a test scheme.
local function pick_scheme(schemes, file)
    local base = vim.fn.fnamemodify(file, ":t:r")
    for _, s in ipairs(schemes) do
        if s == base then return s end
    end
    for _, s in ipairs(schemes) do
        if not s:lower():find("test") then return s end
    end
    return schemes[1]
end

-- Newest available iPhone simulator (a booted one wins).
local function pick_simulator(callback)
    vim.system({ "xcrun", "simctl", "list", "devices", "available", "-j" }, { text = true }, vim.schedule_wrap(function(res)
        local ok, data = pcall(vim.json.decode, res.stdout or "")
        if not ok then return callback(nil) end
        local best
        for runtime, devices in pairs(data.devices or {}) do
            local major, minor = runtime:match("iOS%-(%d+)%-(%d+)")
            if major then
                local version = tonumber(major) * 100 + tonumber(minor)
                for _, d in ipairs(devices) do
                    if d.name:match("^iPhone") then
                        local score = version * 10 + (d.state == "Booted" and 5 or 0) + (d.name:match("Pro$") and 1 or 0)
                        if not best or score > best.score then
                            best = { score = score, id = d.udid, name = d.name, os = major .. "." .. minor }
                        end
                    end
                end
            end
        end
        callback(best)
    end))
end

local function restart_sourcekit(root)
    local bufs = {}
    for _, c in ipairs(vim.lsp.get_clients({ name = "sourcekit" })) do
        if c.root_dir ~= root then
            for b in pairs(c.attached_buffers) do
                if vim.startswith(vim.api.nvim_buf_get_name(b), root .. "/") then table.insert(bufs, b) end
            end
            c:stop()
        end
    end
    if #bufs == 0 then return end
    vim.defer_fn(function()
        local config = vim.tbl_extend("force", vim.lsp.config.sourcekit, { name = "sourcekit", root_dir = root })
        for _, b in ipairs(bufs) do
            if vim.api.nvim_buf_is_valid(b) then vim.lsp.start(config, { bufnr = b }) end
        end
    end, 500)
end

-- Configures xcodebuild.nvim like :XcodebuildSetup would, for iOS apps opened
-- from their root (the plugin keeps its settings in <cwd>/.nvim/xcodebuild).
local function configure_xcodebuild_nvim(root, file, scheme, next)
    local ok, cfg = pcall(require, "xcodebuild.project.config")
    if not ok or cfg.is_configured() or vim.fn.getcwd() ~= root then return next() end
    local xcscheme = vim.fs.find(scheme .. ".xcscheme", { path = root, limit = 1 })[1]
    local xcodeproj = xcscheme and xcscheme:match("^(.-%.xcodeproj)/")
    local pbxproj = xcodeproj and table.concat(vim.fn.readfile(xcodeproj .. "/project.pbxproj"), "\n") or ""
    if not pbxproj:find("SDKROOT = iphoneos", 1, true) then return next() end -- not an iOS app

    pick_simulator(function(sim)
        if not sim then return next() end
        require("xcodebuild.project.appdata").create_app_dir()
        cfg.settings.workingDirectory = root
        cfg.settings.projectFile = file
        cfg.settings.xcodeproj = xcodeproj
        cfg.settings.scheme = scheme
        cfg.settings.platform = "iOS Simulator"
        cfg.settings.destination = sim.id
        cfg.settings.deviceName = sim.name
        cfg.settings.os = sim.os
        cfg.save_settings()
        cfg.update_settings({})
        util.exclude_from_git(root .. "/.nvim")
        notify(("using scheme %s on %s (change with <leader>XS / <leader>Xd)"):format(scheme, sim.name))
        next()
    end)
end

-- Project files whose change calls for a new build (targets, files, packages).
local function project_inputs(root)
    local st = state[root]
    if not st.inputs then
        st.inputs = vim.fs.find(function(name, path)
            return (name == "project.pbxproj" or name == "Package.resolved" or name == "contents.xcworkspacedata")
                and not path:find("/Pods/") and not path:find("/%.build/")
        end, { path = root, limit = math.huge, type = "file" })
    end
    return st.inputs
end

local function newest_build_log(build_root)
    local newest = 0
    for _, log in ipairs(vim.fn.glob(build_root .. "/Logs/Build/*.xcactivitylog", false, true)) do
        local s = vim.uv.fs_stat(log)
        if s and s.mtime.sec > newest then newest = s.mtime.sec end
    end
    return newest
end

-- The compiler flags xcode-build-server extracted from build logs.
local function flags_file(root, scheme)
    local dir = vim.fn.expand("~/Library/Caches/xcode-build-server/") .. root:gsub("/", "-")
    return vim.fn.glob(dir .. "/compile_file-" .. scheme .. "-*", false, true)[1]
end

local function has_flags(root, scheme)
    local f = flags_file(root, scheme)
    local s = f and vim.uv.fs_stat(f)
    return s ~= nil and s.size > 16 -- an empty list is "[]"
end

-- nil, "build" (no/old build) or "clean" (built, but its logs held no compile
-- steps, e.g. everything was up to date: only a full rebuild records flags).
local function needs_build(root, build_root, scheme)
    local last = newest_build_log(build_root)
    if last == 0 then return "build" end
    for _, f in ipairs(project_inputs(root)) do
        local s = vim.uv.fs_stat(f)
        if s and s.mtime.sec > last then return "build" end
    end
    if not has_flags(root, scheme) then return "clean" end
end

-- xcode-build-server picks up a new log within seconds of the build ending.
local function wait_for_flags(root, scheme, since, tries)
    local f = flags_file(root, scheme)
    local s = f and vim.uv.fs_stat(f)
    if s and s.mtime.sec >= since and s.size > 16 then
        return notify("ready: sourcekit has the project's build settings")
    end
    if tries == 0 then
        return notify("build finished, but xcode-build-server hasn't picked it up (see :LspLog)", vim.log.levels.WARN)
    end
    vim.defer_fn(function() wait_for_flags(root, scheme, since, tries - 1) end, 2000)
end

local function build(root, file, flag, scheme, kind)
    local st = state[root]
    -- A build of this project already running (e.g. <leader>Xb) refreshes the
    -- log too; queries like -showBuildSettings or -list don't count.
    local running = vim.system({ "pgrep", "-fl", "xcodebuild" }, { text = true }):wait().stdout or ""
    for line in running:gmatch("[^\n]+") do
        if line:find(vim.fn.fnamemodify(file, ":t"), 1, true) and not line:find(" %-show") and not line:find(" %-list") then
            st.checked_at = nil
            return vim.defer_fn(function() build(root, file, flag, scheme, kind) end, 60000)
        end
    end
    local ok, cfg = pcall(require, "xcodebuild.project.config")
    local dest = ok and cfg.settings.scheme == scheme and cfg.settings.destination
    local name = scheme:gsub("%W", "_")
    local log = ("%s/%s.log"):format(log_dir, name)
    -- Without a result bundle xcodebuild may not write the activity log that
    -- xcode-build-server reads the compiler flags from.
    local result = ("%s/%s.xcresult"):format(log_dir, name)
    vim.fn.delete(result, "rf")

    st.busy = true
    local started = os.time()
    notify(("%s %s in the background for code navigation…")
        :format(kind == "clean" and "rebuilding" or "building", scheme))
    local cmd = { "xcodebuild", flag, file, "-scheme", scheme, "-configuration", "Debug",
        "-destination", dest and ("id=" .. dest) or "generic/platform=iOS Simulator",
        "-skipMacroValidation", "-skipPackagePluginValidation", "-resultBundlePath", result }
    if kind == "clean" then table.insert(cmd, "clean") end
    table.insert(cmd, "build")
    vim.system(cmd, { cwd = root, text = true }, vim.schedule_wrap(function(res)
        st.busy = false
        vim.fn.writefile(vim.split(res.stdout .. res.stderr, "\n"), log)
        if res.code == 0 then
            return wait_for_flags(root, scheme, started, 45)
        end
        local errors = {}
        for line in (res.stdout .. res.stderr):gmatch("[^\n]+") do
            if line:find(" error: ", 1, true) and #errors < 4 then table.insert(errors, line) end
        end
        -- A failed build still updates flags for everything that compiled.
        notify(("background build failed (%s):\n%s"):format(log, table.concat(errors, "\n")),
            vim.log.levels.WARN)
    end))
end

function M.check(buf)
    local path = vim.api.nvim_buf_get_name(buf)
    if path == "" or vim.fn.executable("xcode-build-server") == 0 then return end
    local root = find_root(path)
    if not root then return end -- Swift package or loose file
    local st = state[root] or {}
    state[root] = st
    if st.busy or (st.checked_at and vim.uv.now() - st.checked_at < 30000) then return end
    st.checked_at = vim.uv.now()

    local server = build_server(root)
    if server and server.scheme and (server.workspace or server.project) then
        local file = server.workspace or server.project
        local flag = file:match("%.xcworkspace$") and "-workspace" or "-project"
        st.busy = true -- until the xcodebuild.nvim setup (which picks the simulator) is done
        configure_xcodebuild_nvim(root, file, server.scheme, function()
            st.busy = false
            local kind = needs_build(root, server.build_root, server.scheme)
            if kind then build(root, file, flag, server.scheme, kind) end
        end)
        return
    end

    -- First time: pick a scheme and create buildServer.json.
    local file, flag = project_file(root)
    if not file then return end
    st.busy = true
    notify("setting up " .. vim.fn.fnamemodify(file, ":t") .. " for sourcekit-lsp…")
    vim.system({ "xcodebuild", "-list", "-json", flag, file }, { cwd = root, text = true }, vim.schedule_wrap(function(res)
        local ok, list = pcall(vim.json.decode, res.stdout or "")
        local info = ok and (list.workspace or list.project)
        local scheme = info and info.schemes and pick_scheme(info.schemes, file)
        if not scheme then
            st.busy = false
            return notify("couldn't list schemes: " .. (res.stderr or ""):sub(1, 300), vim.log.levels.ERROR)
        end
        vim.system({ "xcode-build-server", "config", flag, file, "-scheme", scheme }, { cwd = root, text = true },
            vim.schedule_wrap(function(cfg_res)
                st.busy = false
                if cfg_res.code ~= 0 then
                    return notify("xcode-build-server config failed: " .. (cfg_res.stderr or ""), vim.log.levels.ERROR)
                end
                util.exclude_from_git(root .. "/buildServer.json")
                restart_sourcekit(root)
                st.checked_at = nil
                M.check(buf) -- continue with xcodebuild.nvim setup and the build
            end))
    end))
end

vim.api.nvim_create_autocmd({ "BufEnter", "FocusGained" }, {
    group = vim.api.nvim_create_augroup("EnwilIos", {}),
    pattern = { "*.swift", "*.m", "*.mm", "*.h" },
    callback = function(ev) M.check(ev.buf) end,
})

return M
