local agent_mod = require('thorny.agent')
local M = {}

local SEPARATOR = string.rep('─', 60)
local INPUT_PROMPT = '> '

-- Returns the line index (0-based) of the input separator in the buffer
local function get_separator_line(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for i = #lines, 1, -1 do
    if lines[i] == SEPARATOR then return i - 1 end  -- 0-based
  end
  return nil
end

-- Reads user input (lines below the last separator, stripping the prompt prefix)
local function read_input(bufnr)
  local sep = get_separator_line(bufnr)
  if not sep then return '' end
  local lines = vim.api.nvim_buf_get_lines(bufnr, sep + 1, -1, false)
  local parts = {}
  for _, l in ipairs(lines) do
    -- strip leading "> " from first line if present
    if l:sub(1, 2) == INPUT_PROMPT then
      table.insert(parts, l:sub(3))
    else
      table.insert(parts, l)
    end
  end
  return vim.trim(table.concat(parts, '\n'))
end

-- Clears the input area and resets the prompt
local function reset_input(bufnr)
  local sep = get_separator_line(bufnr)
  if not sep then return end
  vim.api.nvim_buf_set_lines(bufnr, sep + 1, -1, false, { INPUT_PROMPT })
  -- move cursor to end of input line
  local win = vim.fn.bufwinid(bufnr)
  if win ~= -1 then
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    vim.api.nvim_win_set_cursor(win, { line_count, #INPUT_PROMPT })
  end
end

-- Appends lines to the history area (above the separator)
local function append_history(bufnr, lines)
  local sep = get_separator_line(bufnr)
  if not sep then return end
  vim.api.nvim_buf_set_lines(bufnr, sep, sep, false, lines)
end

-- Appends a text fragment to the last history line (for streaming)
function M.append_text(a, text)
  if not a.buf or not vim.api.nvim_buf_is_valid(a.buf) then return end
  local bufnr = a.buf
  local sep = get_separator_line(bufnr)
  if not sep then return end
  -- The last history line is sep - 1 (0-based), i.e. line index sep - 1
  local last_line_idx = sep - 1
  if last_line_idx < 0 then
    vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { text })
    return
  end
  local last = vim.api.nvim_buf_get_lines(bufnr, last_line_idx, last_line_idx + 1, false)[1] or ''
  -- Handle newlines in the token by splitting
  local fragment = last .. text
  local new_lines = vim.split(fragment, '\n', { plain = true })
  vim.api.nvim_buf_set_lines(bufnr, last_line_idx, last_line_idx + 1, false, new_lines)
end

-- Renders a pending edit block in the history area
function M.append_tool_use(a, tool_call)
  if not a.buf or not vim.api.nvim_buf_is_valid(a.buf) then return end
  local lines = {
    '',
    '┌─ pending edit: ' .. (tool_call.input.file_path or tool_call.name) .. ' ' .. string.rep('─', 20) .. '┐',
  }
  if tool_call.name == 'Edit' then
    local old = tool_call.input.old_string or ''
    local new = tool_call.input.new_string or ''
    for _, l in ipairs(vim.split(old, '\n', { plain = true })) do
      table.insert(lines, '│  - ' .. l)
    end
    for _, l in ipairs(vim.split(new, '\n', { plain = true })) do
      table.insert(lines, '│  + ' .. l)
    end
  elseif tool_call.name == 'Write' then
    table.insert(lines, '│  [write] ' .. (tool_call.input.file_path or ''))
  elseif tool_call.name == 'MultiEdit' then
    table.insert(lines, '│  [multi-edit] ' .. (tool_call.input.file_path or ''))
  end
  table.insert(lines, '└' .. string.rep('─', 50) .. '┘')
  table.insert(lines, '')
  append_history(a.buf, lines)
end

-- Applies the most recent pending edit to the target file
function M.apply_pending_edit(a)
  local tool_call = agent_mod.pop_pending_edit(a)
  if not tool_call then
    vim.notify('thorny: no pending edits', vim.log.levels.INFO)
    return
  end

  local function apply_edit(file_path, old_string, new_string)
    local abs = file_path:sub(1, 1) == '/' and file_path or (vim.fn.getcwd() .. '/' .. file_path)
    -- Load into a buffer if not already open
    local bufnr = vim.fn.bufnr(abs)
    if bufnr == -1 then
      bufnr = vim.fn.bufadd(abs)
      vim.fn.bufload(bufnr)
    end
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local content = table.concat(lines, '\n')
    local escaped_old = old_string:gsub('[%(%)%.%%%+%-%*%?%[%^%$]', '%%%1')
    local new_content, n = content:gsub(escaped_old, new_string, 1)
    if n == 0 then
      vim.notify('thorny: Edit failed — old_string not found in ' .. file_path, vim.log.levels.ERROR)
      return false
    end
    local new_lines = vim.split(new_content, '\n', { plain = true })
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)
    return true
  end

  local ok = false
  if tool_call.name == 'Edit' then
    ok = apply_edit(tool_call.input.file_path, tool_call.input.old_string, tool_call.input.new_string)
  elseif tool_call.name == 'Write' then
    local abs = tool_call.input.file_path
    if abs:sub(1, 1) ~= '/' then abs = vim.fn.getcwd() .. '/' .. abs end
    local new_lines = vim.split(tool_call.input.content or '', '\n', { plain = true })
    local bufnr = vim.fn.bufadd(abs)
    vim.fn.bufload(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)
    ok = true
  elseif tool_call.name == 'MultiEdit' then
    ok = true
    for _, edit in ipairs(tool_call.input.edits or {}) do
      if not apply_edit(tool_call.input.file_path, edit.old_string, edit.new_string) then
        ok = false
        break
      end
    end
  end

  if ok then
    agent_mod.add_tool_result(a, tool_call.id, 'Edit applied successfully.')
    append_history(a.buf, { '', '✓ edit applied to ' .. (tool_call.input.file_path or tool_call.name), '' })
  end
end

-- send_message: reads input, builds context, calls provider, streams response
local function send_message(a, registry, context_mod, provider_mod)
  local input = read_input(a.buf)
  if input == '' then return end

  reset_input(a.buf)

  -- Add user message to history and render it
  agent_mod.add_message(a, 'user', input)
  append_history(a.buf, { 'You: ' .. input, '' })

  local profile = registry.get_profile(a.profile) or registry.get_profile('default')
  if not profile then
    vim.notify('thorny: no profile "' .. a.profile .. '" found in profiles', vim.log.levels.ERROR)
    return
  end

  local context_str = context_mod.build(a, vim.fn.getcwd())
  local system = a.persona
  if context_str ~= '' then
    system = system .. '\n\n' .. context_str
  end

  -- Marker for the start of this response
  append_history(a.buf, { 'Claude: ' })

  -- Accumulate the full response text during streaming for history
  local response_text = ''

  provider_mod.stream(
    a.history,
    system,
    provider_mod.TOOLS,
    profile,
    {
      on_token = function(text)
        response_text = response_text .. text
        M.append_text(a, text)
      end,
      on_tool_use = function(tool_call)
        agent_mod.add_pending_edit(a, tool_call)
        M.append_tool_use(a, tool_call)
      end,
      on_done = function()
        agent_mod.add_message(a, 'assistant', response_text)
        append_history(a.buf, { '' })
      end,
      on_error = function(msg)
        append_history(a.buf, { '[error: ' .. msg .. ']', '' })
      end,
    }
  )
end

function M.open(a, registry, context_mod, provider_mod)
  -- Reuse existing buffer if valid
  if a.buf and vim.api.nvim_buf_is_valid(a.buf) then
    local win = vim.fn.bufwinid(a.buf)
    if win ~= -1 then vim.api.nvim_set_current_win(win) end
    return a.buf
  end

  local bufnr = vim.api.nvim_create_buf(true, true)
  a.buf = bufnr

  vim.api.nvim_buf_set_name(bufnr, '[thorny] ' .. a.name)
  vim.bo[bufnr].filetype  = 'thorny'
  vim.bo[bufnr].buftype   = 'nofile'
  vim.bo[bufnr].buflisted = true

  -- Initial buffer contents
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    '[thorny] ' .. a.name .. '  |  profile: ' .. a.profile .. '  |  context: ' .. a.context_mode,
    '',
    SEPARATOR,
    INPUT_PROMPT,
  })

  -- Open in a split
  vim.cmd('vsplit')
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, bufnr)
  vim.api.nvim_win_set_cursor(win, { 4, #INPUT_PROMPT })

  -- Keymaps (buffer-local, normal mode)
  local opts = { buffer = bufnr, noremap = true, silent = true }

  vim.keymap.set('n', '<CR>', function()
    send_message(a, registry, context_mod, provider_mod)
  end, opts)

  vim.keymap.set('n', '<leader>ha', function()
    M.apply_pending_edit(a)
  end, opts)

  return bufnr
end

return M
