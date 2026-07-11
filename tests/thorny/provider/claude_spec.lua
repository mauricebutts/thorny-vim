-- These tests mock curl by pointing to a fake shell script that emits SSE.
local claude  = require('thorny.provider.claude')
local uv      = vim.loop

local FAKE_CURL = '/tmp/thorny_fake_curl.sh'

-- Write a fake curl script that emits a two-token text response then exits
local function write_fake_curl_text()
  vim.fn.writefile({
    '#!/bin/sh',
    'printf "data: {\\"type\\":\\"content_block_start\\",\\"index\\":0,\\"content_block\\":{\\"type\\":\\"text\\",\\"text\\":\\"\\"}}\n\n"',
    'printf "data: {\\"type\\":\\"content_block_delta\\",\\"index\\":0,\\"delta\\":{\\"type\\":\\"text_delta\\",\\"text\\":\\"Hello\\"}}\n\n"',
    'printf "data: {\\"type\\":\\"content_block_delta\\",\\"index\\":0,\\"delta\\":{\\"type\\":\\"text_delta\\",\\"text\\":\\" world\\"}}\n\n"',
    'printf "data: {\\"type\\":\\"content_block_stop\\",\\"index\\":0}\n\n"',
    'printf "data: {\\"type\\":\\"message_stop\\"}\n\n"',
  }, FAKE_CURL)
  vim.fn.system('chmod +x ' .. FAKE_CURL)
end

-- Write a fake curl that emits a tool_use block
local function write_fake_curl_tool()
  vim.fn.writefile({
    '#!/bin/sh',
    'printf "data: {\\"type\\":\\"content_block_start\\",\\"index\\":0,\\"content_block\\":{\\"type\\":\\"tool_use\\",\\"id\\":\\"toolu_abc\\",\\"name\\":\\"Edit\\",\\"input\\":{}}}\n\n"',
    'printf "data: {\\"type\\":\\"content_block_delta\\",\\"index\\":0,\\"delta\\":{\\"type\\":\\"input_json_delta\\",\\"partial_json\\":\\"{\\\\\\"file_path\\\\\\":\\\\\\"foo.go\\\\\\",\\"}}\n\n"',
    'printf "data: {\\"type\\":\\"content_block_delta\\",\\"index\\":0,\\"delta\\":{\\"type\\":\\"input_json_delta\\",\\"partial_json\\":\\"{\\\\\\"old_string\\\\\\":\\\\\\"a\\\\\\",\\\\\\"new_string\\\\\\":\\\\\\"b\\\\\\"}}}\n\n"',
    'printf "data: {\\"type\\":\\"content_block_stop\\",\\"index\\":0}\n\n"',
    'printf "data: {\\"type\\":\\"message_stop\\"}\n\n"',
  }, FAKE_CURL)
  vim.fn.system('chmod +x ' .. FAKE_CURL)
end

describe('claude.stream() text', function()
  it('calls on_token for each text delta and on_done at end', function(done)
    write_fake_curl_text()
    claude._curl_cmd = FAKE_CURL

    local tokens = {}
    local done_called = false

    claude.stream(
      { { role = 'user', content = 'hi' } },
      'system',
      {},
      { api_key = 'fake' },
      {
        on_token = function(t) table.insert(tokens, t) end,
        on_tool_use = function(_) end,
        on_done = function()
          done_called = true
          assert.same({ 'Hello', ' world' }, tokens)
          assert.is_true(done_called)
          done()
        end,
        on_error = function(msg) error('unexpected error: ' .. msg) end,
      }
    )
  end)
end)
