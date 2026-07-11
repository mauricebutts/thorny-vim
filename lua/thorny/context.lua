local M = {}

-- Approximate token estimate: 1 token ≈ 4 characters
local MAX_CONTEXT_CHARS = 150000  -- ~37k tokens, safe for Claude's 200k context

-- Use `git ls-files` when available (respects .gitignore), otherwise glob
function M.get_file_tree(root)
  local git_result = vim.fn.systemlist('git -C ' .. vim.fn.shellescape(root) .. ' ls-files 2>/dev/null')
  if vim.v.shell_error == 0 and #git_result > 0 then
    return git_result  -- relative paths from root
  end
  -- fallback: glob all files (no gitignore awareness)
  local files = vim.fn.globpath(root, '**/*', false, true)
  local result = {}
  for _, f in ipairs(files) do
    if vim.fn.isdirectory(f) == 0 then
      -- return relative paths
      local rel = f:sub(#root + 2)
      table.insert(result, rel)
    end
  end
  return result
end

function M.read_file(path)
  if vim.fn.filereadable(path) == 0 then return nil end
  local lines = vim.fn.readfile(path)
  return table.concat(lines, '\n')
end

local function build_project_context(a, cwd)
  local parts = {}

  -- File tree
  local files = M.get_file_tree(cwd)
  table.insert(parts, '<file_tree>\n' .. table.concat(files, '\n') .. '\n</file_tree>')

  local total_chars = #parts[1]

  -- Pinned files first (always included in full)
  for _, path in ipairs(a.pinned_files or {}) do
    local abs = path:sub(1, 1) == '/' and path or (cwd .. '/' .. path)
    local content = M.read_file(abs)
    if content then
      local block = '<file path="' .. path .. '">\n' .. content .. '\n</file>'
      table.insert(parts, block)
      total_chars = total_chars + #block
    end
  end

  -- Remaining files up to token budget
  for _, rel in ipairs(files) do
    if total_chars >= MAX_CONTEXT_CHARS then break end
    local abs = cwd .. '/' .. rel
    local content = M.read_file(abs)
    if content then
      local block = '<file path="' .. rel .. '">\n' .. content .. '\n</file>'
      if total_chars + #block <= MAX_CONTEXT_CHARS then
        table.insert(parts, block)
        total_chars = total_chars + #block
      end
    end
  end

  return table.concat(parts, '\n\n')
end

local function build_buffer_context()
  local bufnr = vim.api.nvim_get_current_buf()
  local name  = vim.api.nvim_buf_get_name(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return '<file path="' .. name .. '">\n' .. table.concat(lines, '\n') .. '\n</file>'
end

function M.build(a, cwd)
  if a.context_mode == 'none' then
    return ''
  elseif a.context_mode == 'buffer' then
    return build_buffer_context()
  else  -- 'project'
    return build_project_context(a, cwd or vim.fn.getcwd())
  end
end

return M
