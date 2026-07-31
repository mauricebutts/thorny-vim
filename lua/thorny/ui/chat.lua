local agent_mod     = require('thorny.agent')
local tool_registry = require('thorny.tools.registry')
local M = {}

local SEPARATOR = string.rep('─', 60)
local INPUT_PROMPT = '> '

-- Temporarily enable modifiable, run fn, then restore to false
local function with_modifiable(bufnr, fn)
  vim.bo[bufnr].modifiable = true
  fn()
  vim.bo[bufnr].modifiable = false
end

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
  with_modifiable(bufnr, function()
    vim.api.nvim_buf_set_lines(bufnr, sep + 1, -1, false, { INPUT_PROMPT })
  end)
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
  with_modifiable(bufnr, function()
    vim.api.nvim_buf_set_lines(bufnr, sep, sep, false, lines)
  end)
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
  with_modifiable(bufnr, function()
    vim.api.nvim_buf_set_lines(bufnr, last_line_idx, last_line_idx + 1, false, new_lines)
  end)
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

-- Rejects the most recent pending edit without applying it
function M.reject_pending_edit(a)
  local tool_call = agent_mod.pop_pending_edit(a)
  if not tool_call then
    vim.notify('thorny: no pending edits', vim.log.levels.INFO)
    return
  end
  agent_mod.add_tool_result(a, tool_call.id, 'User rejected this edit.')
  append_history(a.buf, { '', '✗ edit rejected', '' })
end

-- Applies the most recent pending edit to the target file
function M.apply_pending_edit(a)
  local tool_call = agent_mod.pop_pending_edit(a)
  if not tool_call then
    vim.notify('thorny: no pending edits', vim.log.levels.INFO)
    return
  end

  local spec = tool_registry.get(tool_call.name)
  if not spec or spec.mode ~= 'pending' then
    vim.notify('thorny: unknown pending tool: ' .. tool_call.name, vim.log.levels.WARN)
    return
  end

  local input = tool_call.input
  local cwd   = vim.fn.getcwd()

  local function apply_edit(file_path, old_string, new_string)
    local abs = file_path:sub(1, 1) == '/' and file_path or (cwd .. '/' .. file_path)
    local bufnr = vim.fn.bufnr(abs)
    if bufnr == -1 then
      bufnr = vim.fn.bufadd(abs)
      vim.fn.bufload(bufnr)
    end
    local lines   = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local content = table.concat(lines, '\n')
    local escaped = old_string:gsub('[%(%)%.%%%+%-%*%?%[%^%$]', '%%%1')
    local new_content, n = content:gsub(escaped, new_string, 1)
    if n == 0 then
      vim.notify('thorny: Edit failed — old_string not found in ' .. file_path, vim.log.levels.ERROR)
      return false
    end
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(new_content, '\n', { plain = true }))
    return true
  end

  local ok = false
  if tool_call.name == 'Edit' then
    ok = apply_edit(input.file_path, input.old_string, input.new_string)
  elseif tool_call.name == 'Write' then
    local abs = input.file_path:sub(1, 1) == '/' and input.file_path or (cwd .. '/' .. input.file_path)
    local bufnr = vim.fn.bufadd(abs)
    vim.fn.bufload(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(input.content or '', '\n', { plain = true }))
    ok = true
  elseif tool_call.name == 'MultiEdit' then
    ok = true
    for _, edit in ipairs(input.edits or {}) do
      if not apply_edit(input.file_path, edit.old_string, edit.new_string) then
        ok = false
        break
      end
    end
  else
    vim.notify('thorny: pending tool "' .. tool_call.name .. '" has no built-in apply handler', vim.log.levels.WARN)
    return
  end

  if ok then
    agent_mod.add_tool_result(a, tool_call.id, tool_call.name .. ' applied successfully.')
    append_history(a.buf, { '', '✓ edit applied to ' .. (input.file_path or tool_call.name), '' })
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
    local msg = 'No API profile found. Add your key to ~/.config/nvim/thorny/profiles.json and run :ThornyReloadProfiles'
    append_history(a.buf, { '', '[thorny error] ' .. msg, '' })
    vim.notify('thorny: ' .. msg, vim.log.levels.ERROR)
    return
  end

  -- Build system prompt once per session; reuse cached value on subsequent sends
  if not a._cached_system then
    local context_str = context_mod.build(a, vim.fn.getcwd())
    a._cached_system = a.persona
    if context_str ~= '' then
      a._cached_system = a._cached_system .. '\n\n' .. context_str
    end
  end
  local system = a._cached_system

  -- Marker for the start of this response
  append_history(a.buf, { 'Claude: ' })

  local response_text = ''

  local callbacks
  callbacks = {
    on_token = function(text)
      response_text = response_text .. text
      M.append_text(a, text)
    end,

    on_tool_use = function(tool_call)
      local spec = tool_registry.get(tool_call.name)
      if spec and spec.mode == 'pending' then
        agent_mod.add_pending_edit(a, tool_call)
        M.append_tool_use(a, tool_call)
      end
      -- auto-mode tools (ReadFile) are handled silently in on_tools_done
    end,

    -- stop_reason == 'tool_use': all client tool calls for this turn are done.
    -- Add the full assistant turn to history, execute auto tools and re-send,
    -- or park at the pending-edit UI.
    on_tools_done = function(content_blocks)
      table.insert(a.history, { role = 'assistant', content = content_blocks })
      response_text = ''  -- reset; next turn accumulates fresh text

      local has_auto = false
      for _, blk in ipairs(content_blocks) do
        if blk.type == 'tool_use' then
          local spec = tool_registry.get(blk.name)
          if spec and spec.mode == 'auto' then
            has_auto = true
            local ctx    = { cwd = vim.fn.getcwd() }
            local result = spec.execute(blk.input, ctx)
            agent_mod.add_tool_result(a, blk.id, result)
            local label = blk.input.file_path or blk.input.path or blk.name
            append_history(a.buf, { '[' .. blk.name .. ': ' .. label .. ']' })
          elseif has_auto then
            -- Mixed turn: auto + pending. Add placeholder so the API accepts
            -- the re-send; the pending edit was already shown via on_tool_use.
            agent_mod.add_tool_result(a, blk.id, 'Deferred: awaiting file reads in this turn.')
          end
        end
      end

      if has_auto then
        provider_mod.stream(a.history, system, nil, profile, callbacks)
      else
        -- Pure pending-edit turn — wait for user to press <leader>ha
        append_history(a.buf, { '' })
        require('thorny.persist').save_agent(a)
      end
    end,

    -- pause_turn: Anthropic is executing a server tool (e.g. web_search).
    -- Push the partial assistant turn to history so Anthropic can inject the
    -- tool result on the re-send, then fire the stream again.
    on_pause = function(content_blocks)
      table.insert(a.history, { role = 'assistant', content = content_blocks })
      provider_mod.stream(a.history, system, nil, profile, callbacks)
    end,

    on_done = function()
      agent_mod.add_message(a, 'assistant', response_text)
      append_history(a.buf, { '' })
      require('thorny.persist').save_agent(a)
    end,

    on_error = function(msg)
      append_history(a.buf, { '[error: ' .. msg .. ']', '' })
    end,
  }
  provider_mod.stream(a.history, system, nil, profile, callbacks)
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

  -- Warn immediately if no profile is configured
  local profile_warning = {}
  local profile_ok = registry.get_profile(a.profile) or registry.get_profile('default')
  if not profile_ok then
    profile_warning = {
      '[thorny] No API key configured. Add one to ~/.config/nvim/thorny/profiles.json',
      '[thorny] then run :ThornyReloadProfiles',
      '',
    }
  end

  -- History area is read-only. Any insert-mode key jumps cursor to the
  -- input area and unlocks the buffer; InsertLeave locks it back.
  vim.bo[bufnr].modifiable = false

  local function jump_to_input()
    vim.bo[bufnr].modifiable = true
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    vim.api.nvim_win_set_cursor(0, { line_count, vim.fn.col('$') })
  end

  vim.api.nvim_create_autocmd('InsertLeave', {
    buffer = bufnr,
    callback = function() vim.bo[bufnr].modifiable = false end,
  })

  -- Initial buffer contents
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.list_extend({
    '[thorny] ' .. a.name .. '  |  profile: ' .. a.profile .. '  |  context: ' .. a.context_mode,
    '',
  }, vim.list_extend(profile_warning, {
    SEPARATOR,
    INPUT_PROMPT,
  })))
  vim.bo[bufnr].modifiable = false

  -- Open in a split
  vim.cmd('vsplit')
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, bufnr)
  vim.api.nvim_win_set_cursor(win, { 4, #INPUT_PROMPT })

  -- Keymaps (buffer-local, normal mode)
  local opts = { buffer = bufnr, noremap = true, silent = true }

  -- All insert-mode entry keys jump to the input area instead of editing in place
  for _, key in ipairs({ 'i', 'I', 'a', 'A', 'o', 'O', 's', 'S' }) do
    vim.keymap.set('n', key, function()
      jump_to_input()
      vim.cmd('startinsert!')  -- 'A' behaviour: cursor at end of line
    end, opts)
  end

  -- Paste keys append to the input area
  for _, key in ipairs({ 'p', 'P' }) do
    vim.keymap.set('n', key, function()
      local line_count = vim.api.nvim_buf_line_count(bufnr)
      vim.api.nvim_win_set_cursor(0, { line_count, vim.fn.col('$') })
      with_modifiable(bufnr, function()
        vim.cmd('normal! p')
      end)
    end, opts)
  end

  vim.keymap.set('n', '<CR>', function()
    send_message(a, registry, context_mod, provider_mod)
  end, opts)

  vim.keymap.set('n', '<leader>ha', function()
    M.apply_pending_edit(a)
  end, opts)

  vim.keymap.set('n', '<leader>hr', function()
    M.reject_pending_edit(a)
  end, opts)

  vim.keymap.set('n', '<leader>ac', function()
    local picker_mod = require('thorny.ui.picker')
    picker_mod.pick_context_files(vim.fn.getcwd(), function(file)
      a.pinned_files = a.pinned_files or {}
      table.insert(a.pinned_files, file)
      a._cached_system = nil  -- force context rebuild on next send
      append_history(bufnr, { '[pinned: ' .. file .. ']' })
      vim.notify('thorny: pinned ' .. file, vim.log.levels.INFO)
    end)
  end, opts)

  return bufnr
end

return M
