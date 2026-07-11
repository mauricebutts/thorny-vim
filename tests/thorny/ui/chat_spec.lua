local chat      = require('thorny.ui.chat')
local agent_mod = require('thorny.agent')

describe('chat.open()', function()
  it('creates a buffer and assigns it to agent.buf', function()
    local a = agent_mod.new('chat-test', 'persona', 'default', 'none')
    local mock_registry = { get_profile = function() return { api_key = 'fake' } end }
    local mock_context  = { build = function() return '' end }
    local mock_provider = { stream = function() end }

    local bufnr = chat.open(a, mock_registry, mock_context, mock_provider)
    assert.is_number(bufnr)
    assert.equals(bufnr, a.buf)
    assert.equals('thorny', vim.bo[bufnr].filetype)
  end)

  it('returns the same buffer on second call', function()
    local a = agent_mod.new('chat-test2', '', 'default', 'none')
    local mock_registry = { get_profile = function() return { api_key = 'fake' } end }
    local mock_context  = { build = function() return '' end }
    local mock_provider = { stream = function() end }

    local b1 = chat.open(a, mock_registry, mock_context, mock_provider)
    local b2 = chat.open(a, mock_registry, mock_context, mock_provider)
    assert.equals(b1, b2)
  end)
end)

describe('chat.append_text()', function()
  it('appends text to the buffer history area', function()
    local a = agent_mod.new('append-test', '', 'default', 'none')
    local mock_registry = { get_profile = function() return { api_key = 'fake' } end }
    chat.open(a, mock_registry, { build = function() return '' end }, { stream = function() end })
    chat.append_text(a, 'hello from claude')
    local lines = vim.api.nvim_buf_get_lines(a.buf, 0, -1, false)
    local found = false
    for _, l in ipairs(lines) do
      if l:find('hello from claude') then found = true end
    end
    assert.is_true(found)
  end)
end)

describe('chat.apply_pending_edit()', function()
  it('applies an Edit tool_call to a buffer', function()
    local tmp = '/tmp/thorny_chat_edit_test.txt'
    vim.fn.writefile({ 'old content' }, tmp)

    local a = agent_mod.new('edit-test', '', 'default', 'none')
    local mock_registry = { get_profile = function() return { api_key = 'fake' } end }
    chat.open(a, mock_registry, { build = function() return '' end }, { stream = function() end })

    agent_mod.add_pending_edit(a, {
      id    = 'toolu_x',
      name  = 'Edit',
      input = { file_path = tmp, old_string = 'old content', new_string = 'new content' },
    })

    chat.apply_pending_edit(a)

    local result = vim.fn.readfile(tmp)
    assert.equals('new content', result[1])
    assert.equals(0, #a.pending_edits)

    vim.fn.delete(tmp)
  end)
end)
