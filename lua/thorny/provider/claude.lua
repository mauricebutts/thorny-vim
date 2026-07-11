local M = {}

-- Override in tests to point at a fake curl script
M._curl_cmd = 'curl'

local TOOLS = {
  {
    name        = 'Edit',
    description = 'Replace exact text in a file. old_string must match exactly (including whitespace).',
    input_schema = {
      type       = 'object',
      properties = {
        file_path  = { type = 'string', description = 'Path to the file to edit' },
        old_string = { type = 'string', description = 'The exact text to replace' },
        new_string = { type = 'string', description = 'The replacement text' },
      },
      required = { 'file_path', 'old_string', 'new_string' },
    },
  },
  {
    name        = 'Write',
    description = 'Write complete contents to a file, creating it if it does not exist.',
    input_schema = {
      type       = 'object',
      properties = {
        file_path = { type = 'string', description = 'Path to the file to write' },
        content   = { type = 'string', description = 'The full file contents' },
      },
      required = { 'file_path', 'content' },
    },
  },
  {
    name        = 'MultiEdit',
    description = 'Apply multiple Edit operations to a single file.',
    input_schema = {
      type       = 'object',
      properties = {
        file_path = { type = 'string', description = 'Path to the file to edit' },
        edits     = {
          type  = 'array',
          items = {
            type       = 'object',
            properties = {
              old_string = { type = 'string' },
              new_string = { type = 'string' },
            },
            required = { 'old_string', 'new_string' },
          },
        },
      },
      required = { 'file_path', 'edits' },
    },
  },
}

M.TOOLS = TOOLS

function M.stream(messages, system, tools, profile, callbacks)
  local body = vim.json.encode({
    model      = 'claude-opus-4-6',
    max_tokens = 8192,
    stream     = true,
    system     = system,
    messages   = messages,
    tools      = tools or TOOLS,
  })

  local stdout = vim.loop.new_pipe(false)
  local stderr = vim.loop.new_pipe(false)

  -- SSE parser state
  local line_buf      = ''
  local current_block = nil   -- {type, id, name} for tool_use blocks
  local tool_json_buf = ''    -- accumulates partial_json for tool_use input

  local function handle_event(event)
    if event.type == 'content_block_start' then
      current_block = event.content_block
      tool_json_buf = ''

    elseif event.type == 'content_block_delta' then
      local delta = event.delta
      if delta.type == 'text_delta' then
        vim.schedule(function()
          callbacks.on_token(delta.text)
        end)
      elseif delta.type == 'input_json_delta' then
        tool_json_buf = tool_json_buf .. (delta.partial_json or '')
      end

    elseif event.type == 'content_block_stop' then
      if current_block and current_block.type == 'tool_use' then
        local ok, input = pcall(vim.json.decode, tool_json_buf)
        if ok then
          local tool_call = { id = current_block.id, name = current_block.name, input = input }
          vim.schedule(function()
            callbacks.on_tool_use(tool_call)
          end)
        end
        current_block = nil
        tool_json_buf = ''
      end

    elseif event.type == 'message_stop' then
      vim.schedule(function()
        callbacks.on_done()
      end)
    end
  end

  local function on_stdout(err, data)
    if err or not data then return end
    line_buf = line_buf .. data
    while true do
      local nl = line_buf:find('\n')
      if not nl then break end
      local line = line_buf:sub(1, nl - 1):gsub('\r$', '')
      line_buf = line_buf:sub(nl + 1)
      if line:sub(1, 6) == 'data: ' then
        local json_str = line:sub(7)
        if json_str ~= '[DONE]' then
          local ok, event = pcall(vim.json.decode, json_str)
          if ok then handle_event(event) end
        end
      end
    end
  end

  local args
  if M._curl_cmd ~= 'curl' then
    -- test mode: run the fake script directly, ignore all other args
    args = {}
  else
    args = {
      '-s', '-N', '--no-buffer',
      '-X', 'POST',
      'https://api.anthropic.com/v1/messages',
      '-H', 'Content-Type: application/json',
      '-H', 'anthropic-version: 2023-06-01',
      '-H', 'x-api-key: ' .. profile.api_key,
      '-d', body,
    }
  end

  local handle
  handle = vim.loop.spawn(M._curl_cmd, {
    args  = args,
    stdio = { nil, stdout, stderr },
  }, function(code)
    stdout:close()
    stderr:close()
    handle:close()
    if code ~= 0 then
      vim.schedule(function()
        callbacks.on_error('curl exited with code ' .. code)
      end)
    end
  end)

  stdout:read_start(on_stdout)
  stderr:read_start(function() end) -- drain stderr silently
end

return M
