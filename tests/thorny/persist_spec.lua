local agent   = require('thorny.agent')
local persist = require('thorny.persist')

local TEST_DIR = '/tmp/thorny_test_persist'

-- Override persist dir for tests
persist._dir = TEST_DIR

before_each(function()
  vim.fn.mkdir(TEST_DIR, 'p')
end)

after_each(function()
  vim.fn.delete(TEST_DIR, 'rf')
end)

describe('persist.save_agent / load_agent', function()
  it('round-trips an agent to disk and back', function()
    local a = agent.new('persist-test', 'You persist.', 'personal', 'buffer')
    agent.add_message(a, 'user', 'hello')
    agent.add_message(a, 'assistant', 'world')

    persist.save_agent(a)

    local loaded = persist.load_agent('persist-test')
    assert.is_not_nil(loaded)
    assert.equals('persist-test', loaded.name)
    assert.equals('You persist.', loaded.persona)
    assert.equals('personal', loaded.profile)
    assert.equals('buffer', loaded.context_mode)
    assert.equals(2, #loaded.history)
    assert.equals('hello', loaded.history[1].content)
    assert.equals('world', loaded.history[2].content)
  end)

  it('load_agent returns nil for a missing file', function()
    assert.is_nil(persist.load_agent('no-such-agent'))
  end)
end)

describe('persist.load_all_agents', function()
  it('loads all saved agents from the dir', function()
    persist.save_agent(agent.new('aa', '', 'default', 'none'))
    persist.save_agent(agent.new('bb', '', 'default', 'none'))

    local all = persist.load_all_agents()
    local names = {}
    for _, a in ipairs(all) do names[a.name] = true end
    assert.is_true(names['aa'])
    assert.is_true(names['bb'])
  end)

  it('returns empty list when dir has no agent files', function()
    local all = persist.load_all_agents()
    assert.same({}, all)
  end)
end)

describe('persist.load_profiles', function()
  it('loads a profiles.json file', function()
    local path = TEST_DIR .. '/profiles.json'
    local data = vim.json.encode({ default = { api_key = 'sk-test' } })
    vim.fn.writefile({ data }, path)

    local profiles = persist.load_profiles(path)
    assert.equals('sk-test', profiles['default'].api_key)
  end)

  it('returns empty table when profiles file does not exist', function()
    local profiles = persist.load_profiles(TEST_DIR .. '/missing.json')
    assert.same({}, profiles)
  end)
end)
