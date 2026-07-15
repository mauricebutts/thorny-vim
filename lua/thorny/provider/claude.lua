local M = {}

-- Override in tests to point at a fake curl script
M._curl_cmd = 'curl'

local registry = require('thorny.tools.registry')

function M.stream(messages, system, tools, profile, callbacks)
  -- System prompt sent as an array so Anthropic can cache it between turns
  local system_payload = {
    { type = 'text', text = system, cache_control = { type = 'ephemeral' } }
  }

  local body = vim.json.encode({
    model      = 'claude-opus-4-6',
    max_tokens = 8192,
    stream     = true,
    system     = system_payload,
    messages   = messages,
    tools      = tools or registry.get_definitions(),
  })

  local stdout = vim.loop.new_pipe(false)
  local stderr = vim.loop.new_pipe(false)

  -- SSE parser state
  local line_buf           = ''
  local current_block      = nil  -- content block currently being streamed
  local tool_json_buf      = ''   -- accumulates partial_json for tool input
  local accumulated_blocks = {}   -- all content blocks for this turn (for pause_turn re-send)
  local is_pause           = false
  local is_tool_use        = false

  local function handle_event(event)
    if event.type == 'content_block_start' then
      current_block = event.content_block
      tool_json_buf = ''
      local cb_type = current_block.type
      if cb_type == 'text' then
        table.insert(accumulated_blocks, { type = 'text', text = '' })
      elseif cb_type == 'server_tool_use' then
        -- Anthropic is executing a server-side tool; show indicator, track for re-send
        table.insert(accumulated_blocks, {
          type  = 'server_tool_use',
          id    = current_block.id,
          name  = current_block.name,
          input = {},
        })
        vim.schedule(function()
          callbacks.on_token('\n[searching the web...]\n')
        end)
      end
      -- web_search_tool_result blocks are visible in the stream for context but
      -- require no client action; we intentionally do not accumulate them.

    elseif event.type == 'content_block_delta' then
      local delta = event.delta
      if delta.type == 'text_delta' then
        -- Keep accumulated text block in sync for pause_turn re-send
        for i = #accumulated_blocks, 1, -1 do
          if accumulated_blocks[i].type == 'text' then
            accumulated_blocks[i].text = accumulated_blocks[i].text .. delta.text
            break
          end
        end
        vim.schedule(function()
          callbacks.on_token(delta.text)
        end)
      elseif delta.type == 'input_json_delta' then
        tool_json_buf = tool_json_buf .. (delta.partial_json or '')
      end

    elseif event.type == 'content_block_stop' then
      if current_block then
        local cb_type = current_block.type
        if cb_type == 'tool_use' then
          local ok, input = pcall(vim.json.decode, tool_json_buf)
          if ok then
            table.insert(accumulated_blocks, {
              type  = 'tool_use',
              id    = current_block.id,
              name  = current_block.name,
              input = input,
            })
            local tool_call = { id = current_block.id, name = current_block.name, input = input }
            vim.schedule(function()
              callbacks.on_tool_use(tool_call)
            end)
          end
        elseif cb_type == 'server_tool_use' then
          -- Finalise the input field on the accumulated block
          local ok, input = pcall(vim.json.decode, tool_json_buf)
          if ok then
            for i = #accumulated_blocks, 1, -1 do
              local blk = accumulated_blocks[i]
              if blk.type == 'server_tool_use' and blk.id == current_block.id then
                blk.input = input
                break
              end
            end
          end
        end
        current_block = nil
        tool_json_buf = ''
      end

    elseif event.type == 'message_delta' then
      local stop_reason = event.delta and event.delta.stop_reason
      if stop_reason == 'pause_turn' then
        -- Anthropic is executing a server tool; re-send so it can inject the result.
        is_pause = true
        if callbacks.on_pause then
          vim.schedule(function()
            callbacks.on_pause(accumulated_blocks)
          end)
        end
      elseif stop_reason == 'tool_use' then
        -- Client tool calls are complete for this turn; dispatch them.
        is_tool_use = true
        if callbacks.on_tools_done then
          vim.schedule(function()
            callbacks.on_tools_done(accumulated_blocks)
          end)
        end
      end

    elseif event.type == 'message_stop' then
      if not is_pause and not is_tool_use then
        vim.schedule(function()
          callbacks.on_done()
        end)
      end
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

  -- Write API key to a temp curl config file so it never appears in ps aux
  local tmpfile = os.tmpname()
  do
    local f = io.open(tmpfile, 'w')
    if f then
      f:write('header = "x-api-key: ' .. profile.api_key .. '"\n')
      f:close()
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
      '-H', 'anthropic-beta: prompt-caching-2024-07-31',
      '--config', tmpfile,
      '-d', body,
    }
  end

  local handle
  handle = vim.loop.spawn(M._curl_cmd, {
    args  = args,
    stdio = { nil, stdout, stderr },
  }, function(code)
    os.remove(tmpfile)  -- delete key file as soon as curl exits
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
