local M = {}

-- Hides a generated file from git for this clone only (.git/info/exclude),
-- unless git already tracks or ignores it.
function M.exclude_from_git(path)
    local repo = vim.fs.root(path, ".git")
    local exclude = repo and repo .. "/.git/info/exclude"
    if not exclude or not vim.uv.fs_stat(vim.fs.dirname(exclude)) then return end
    local check = vim.system({ "git", "ls-files", "--error-unmatch", path }, { cwd = repo }):wait()
    local ignored = vim.system({ "git", "check-ignore", "-q", path }, { cwd = repo }):wait()
    if check.code == 0 or ignored.code == 0 then return end
    local entry = "/" .. vim.fs.relpath(repo, path)
    local lines = vim.uv.fs_stat(exclude) and vim.fn.readfile(exclude) or {}
    if not vim.tbl_contains(lines, entry) then
        table.insert(lines, entry)
        vim.fn.writefile(lines, exclude)
    end
end

return M
