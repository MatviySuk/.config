-- Android workflow on top of Gradle + adb: build, install & launch, unit
-- tests, logcat, device / emulator selection. Build errors land in quickfix.
--
-- Per-project overrides (e.g. in an exrc or before running):
--   vim.g.android_module  = "app"    -- Gradle module to build
--   vim.g.android_variant = "debug"  -- e.g. "freeDebug" for flavors

local M = {}

local sdk = vim.env.ANDROID_HOME or vim.env.ANDROID_SDK_ROOT
    or vim.fn.expand("~/Library/Android/sdk")

-- Neovim may be started from a shell that does not export the SDK / JDK.
if vim.fn.isdirectory(sdk) == 1 then
    vim.env.ANDROID_HOME = sdk
    vim.env.PATH = sdk .. "/platform-tools:" .. sdk .. "/emulator:" .. vim.env.PATH
end
local studio_jbr = "/Applications/Android Studio.app/Contents/jbr/Contents/Home"
if not vim.env.JAVA_HOME and vim.fn.isdirectory(studio_jbr) == 1 then
    -- Same JDK Android Studio builds with, so Gradle/AGP versions line up.
    vim.env.JAVA_HOME = studio_jbr
end

local log_file = vim.fn.stdpath("cache") .. "/android-gradle.log"
local term_win

local function module() return vim.g.android_module or "app" end
local function variant() return vim.g.android_variant or "debug" end
local function Variant() return (variant():gsub("^%l", string.upper)) end

local function project_root()
    local root = vim.fs.root(0, "gradlew") or vim.fs.root(vim.fn.getcwd(), "gradlew")
    if not root then
        vim.notify("No gradlew found above the current file or cwd", vim.log.levels.ERROR)
    end
    return root
end

local function adb(args)
    local res = vim.system(vim.list_extend({ "adb" }, args), { text = true }):wait()
    return vim.trim(res.stdout or ""), res.code
end

-- Reads the real applicationId (suffixes and flavors included) from the APK.
local function package_name(root)
    local apk_dir = ("%s/%s/build/outputs/apk/%s"):format(root, module(),
        variant():gsub("(%l)(%u)", "%1/%2"):lower())
    local apk = vim.fn.glob(apk_dir .. "/*.apk", false, true)[1]
    local aapt2 = vim.fn.glob(sdk .. "/build-tools/*/aapt2", false, true)
    if not apk or #aapt2 == 0 then return nil end
    local res = vim.system({ aapt2[#aapt2], "dump", "packagename", apk }, { text = true }):wait()
    return res.code == 0 and vim.trim(res.stdout) or nil
end

local function open_term(cmd, root, on_exit)
    vim.cmd("botright 15new")
    if term_win and vim.api.nvim_win_is_valid(term_win) then
        vim.api.nvim_win_close(term_win, true)
    end
    term_win = vim.api.nvim_get_current_win()
    vim.fn.jobstart(cmd, { term = true, cwd = root, on_exit = on_exit })
    vim.cmd("normal! G")
    vim.cmd.wincmd("p")
end

local function load_quickfix()
    vim.fn.setqflist({}, " ", {
        title = "Gradle",
        lines = vim.fn.readfile(log_file),
        efm = table.concat({
            "%t: file://%f:%l:%c %m", -- Kotlin 2.x ("e: file:///...")
            "%t: %f: (%l\\, %c): %m", -- Kotlin 1.x
            "%f:%l: %trror: %m", -- Java
            "%f:%l: %tarning: %m",
            "%-G%.%#",
        }, ","),
    })
    if #vim.fn.getqflist() > 0 then vim.cmd("copen") end
end

-- Runs Gradle tasks in a terminal split; parses errors into quickfix on failure.
function M.gradle(tasks, on_success)
    local root = project_root()
    if not root then return end
    local cmd = ("set -o pipefail; ./gradlew %s 2>&1 | tee %s"):format(
        table.concat(tasks, " "), vim.fn.shellescape(log_file))
    open_term({ "bash", "-c", cmd }, root, function(_, code)
        vim.schedule(function()
            if code == 0 then
                vim.fn.setqflist({}, "r")
                if on_success then on_success(root) end
            else
                load_quickfix()
                vim.notify("Gradle failed: " .. table.concat(tasks, " "), vim.log.levels.ERROR)
            end
        end)
    end)
end

local function task(name) return (":%s:%s"):format(module(), name) end

function M.build() M.gradle({ task("assemble" .. Variant()) }) end

function M.test() M.gradle({ task("test" .. Variant() .. "UnitTest") }) end

function M.clean() M.gradle({ "clean" }) end

function M.run()
    M.gradle({ task("install" .. Variant()) }, function(root)
        local pkg = package_name(root)
        if not pkg then
            vim.notify("Installed, but could not determine the package name", vim.log.levels.WARN)
            return
        end
        vim.g.android_package = pkg
        adb({ "shell", "monkey", "-p", pkg, "-c", "android.intent.category.LAUNCHER", "1" })
        vim.notify("Launched " .. pkg)
    end)
end

function M.stop()
    local pkg = vim.g.android_package
    if not pkg then return vim.notify("Run the app first (:AndroidRun)", vim.log.levels.WARN) end
    adb({ "shell", "am", "force-stop", pkg })
end

-- `all` = unfiltered logcat; otherwise only the last launched app's process.
function M.logcat(all)
    local cmd = { "adb", "logcat", "-v", "color" }
    local pkg = vim.g.android_package
    if not all then
        if not pkg then return vim.notify("Run the app first, or use :AndroidLogcat!", vim.log.levels.WARN) end
        local pid = adb({ "shell", "pidof", "-s", pkg })
        if pid == "" then return vim.notify(pkg .. " is not running", vim.log.levels.WARN) end
        vim.list_extend(cmd, { "--pid=" .. pid })
    end
    open_term(cmd, vim.fn.getcwd())
end

-- Sets ANDROID_SERIAL, which both adb and Gradle's install tasks honor.
function M.select_device()
    local out = adb({ "devices", "-l" })
    local devices = {}
    for line in out:gmatch("[^\n]+") do
        local serial, rest = line:match("^(%S+)%s+device%s*(.*)$")
        if serial then table.insert(devices, { serial = serial, desc = rest }) end
    end
    if #devices == 0 then
        return vim.notify("No devices connected (:AndroidEmulator to start one)", vim.log.levels.WARN)
    end
    vim.ui.select(devices, {
        prompt = "Android device",
        format_item = function(d) return d.serial .. "  " .. (d.desc:match("model:(%S+)") or d.desc) end,
    }, function(d)
        if d then
            vim.env.ANDROID_SERIAL = d.serial
            vim.notify("Android device: " .. d.serial)
        end
    end)
end

function M.start_emulator()
    local res = vim.system({ "emulator", "-list-avds" }, { text = true }):wait()
    local avds = vim.split(vim.trim(res.stdout or ""), "\n", { trimempty = true })
    if #avds == 0 then return vim.notify("No AVDs found", vim.log.levels.WARN) end
    vim.ui.select(avds, { prompt = "Start emulator" }, function(avd)
        if avd then
            vim.fn.jobstart({ "emulator", "-avd", avd }, { detach = true })
            vim.notify("Starting " .. avd)
        end
    end)
end

local cmd = vim.api.nvim_create_user_command
cmd("AndroidBuild", M.build, { desc = "Gradle assemble" })
cmd("AndroidRun", M.run, { desc = "Install & launch" })
cmd("AndroidStop", M.stop, { desc = "Force-stop the app" })
cmd("AndroidTest", M.test, { desc = "Run unit tests" })
cmd("AndroidClean", M.clean, { desc = "Gradle clean" })
cmd("AndroidLogcat", function(o) M.logcat(o.bang) end, { bang = true, desc = "Logcat (! = all)" })
cmd("AndroidDevice", M.select_device, { desc = "Select device" })
cmd("AndroidEmulator", M.start_emulator, { desc = "Start an emulator" })
cmd("Gradle", function(o) M.gradle(o.fargs) end, { nargs = "+", desc = "Run Gradle tasks" })

local map = function(lhs, rhs, desc) vim.keymap.set("n", lhs, rhs, { desc = desc }) end
map("<leader>Ab", M.build, "Android: build")
map("<leader>Ar", M.run, "Android: install & run")
map("<leader>As", M.stop, "Android: stop app")
map("<leader>At", M.test, "Android: unit tests")
map("<leader>Ac", M.clean, "Android: clean")
map("<leader>Al", function() M.logcat(false) end, "Android: app logcat")
map("<leader>AL", function() M.logcat(true) end, "Android: full logcat")
map("<leader>Ad", M.select_device, "Android: select device")
map("<leader>Ae", M.start_emulator, "Android: start emulator")
map("<leader>Ag", ":Gradle ", "Android: run Gradle task")
map("<leader>Ak", "<cmd>KotlinSync<cr>", "Android: load libraries into kotlin-lsp")

return M
