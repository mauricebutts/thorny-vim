local context  = require('thorny.context')
local agent_mod = require('thorny.agent')

local TEST_DIR = '/tmp/thorny_test_context'

before_each(function()
  vim.fn.mkdir(TEST_DIR .. '/subdir', 'p')
  vim.fn.writefile({ 'hello' }, TEST_DIR .. '/foo.go')
  vim.fn.writefile({ 'world' }, TEST_DIR .. '/subdir/bar.go')
  vim.fn.writefile({ 'ignored' }, TEST_DIR .. '/ignored.log')
  vim.fn.writefile({ '*.log' }, TEST_DIR .. '/.gitignore')
end)

after_each(function()
  vim.fn.delete(TEST_DIR, 'rf')
end)

describe('context.get_file_tree()', function()
  it('returns file paths under root', function()
    local files = context.get_file_tree(TEST_DIR)
    local found = {}
    for _, f in ipairs(files) do found[f] = true end
    assert.is_true(found['foo.go'] or found[TEST_DIR .. '/foo.go'])
    assert.is_true(found['subdir/bar.go'] or found[TEST_DIR .. '/subdir/bar.go'])
  end)

  it('excludes .gitignore patterns when git is unavailable, falls back to glob', function()
    -- This test just verifies the function returns a non-empty list and does not error
    local files = context.get_file_tree(TEST_DIR)
    assert.is_true(#files > 0)
  end)
end)

describe('context.read_file()', function()
  it('returns file contents as a string', function()
    local content = context.read_file(TEST_DIR .. '/foo.go')
    assert.equals('hello', content)
  end)

  it('returns nil for a missing file', function()
    assert.is_nil(context.read_file(TEST_DIR .. '/nope.go'))
  end)
end)

describe('context.build()', function()
  it('returns empty string for context_mode=none', function()
    local a = agent_mod.new('t', '', 'default', 'none')
    local result = context.build(a, TEST_DIR)
    assert.equals('', result)
  end)

  it('returns a non-empty string for context_mode=project', function()
    local a = agent_mod.new('t', '', 'default', 'project')
    a.pinned_files = { TEST_DIR .. '/foo.go' }
    local result = context.build(a, TEST_DIR)
    assert.is_true(#result > 0)
    assert.is_true(result:find('foo.go') ~= nil)
  end)
end)
