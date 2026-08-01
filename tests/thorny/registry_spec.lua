local agent    = require('thorny.agent')
local registry = require('thorny.registry')

describe('registry agents', function()
  before_each(function()
    registry.setup({
      default = { api_key = 'sk-ant-test' },
      work    = { api_key = 'sk-ant-work' },
    })
  end)

  it('adds and retrieves an agent by name', function()
    local a = agent.new('debug', 'You debug.', 'default', 'buffer')
    registry.add_agent(a)
    local found = registry.get_agent('debug')
    assert.equals('debug', found.name)
  end)

  it('list_agents returns all agents', function()
    registry.add_agent(agent.new('a1', '', 'default', 'none'))
    registry.add_agent(agent.new('a2', '', 'default', 'none'))
    local list = registry.list_agents()
    assert.is_true(#list >= 2)
  end)

  it('remove_agent removes by name', function()
    registry.add_agent(agent.new('removeme', '', 'default', 'none'))
    registry.remove_agent('removeme')
    assert.is_nil(registry.get_agent('removeme'))
  end)

  it('get_agent returns nil for unknown agent', function()
    assert.is_nil(registry.get_agent('does_not_exist'))
  end)
end)

describe('registry profiles', function()
  before_each(function()
    registry.setup({
      default = { api_key = 'sk-ant-test' },
      work    = { api_key = 'sk-ant-work' },
    })
  end)

  it('get_profile returns a profile by name', function()
    local p = registry.get_profile('work')
    assert.equals('sk-ant-work', p.api_key)
  end)

  it('get_profile returns nil for unknown profile', function()
    assert.is_nil(registry.get_profile('unknown'))
  end)

  it('list_profiles returns all profile names', function()
    local profiles = registry.list_profiles()
    local names = {}
    for _, p in ipairs(profiles) do names[p.name] = true end
    assert.is_true(names['default'])
    assert.is_true(names['work'])
  end)

  it('set_agent_profile switches the profile field', function()
    local a = agent.new('switcher', '', 'default', 'none')
    registry.add_agent(a)
    registry.set_agent_profile(a, 'work')
    assert.equals('work', a.profile)
  end)
end)

describe('registry set_agent_provider', function()
  before_each(function()
    registry.setup({
      default = { api_key = 'sk-ant-test' },
    })
  end)

  it('switches the provider field on the agent', function()
    local a = agent.new('switcher', '', 'default', 'none', 'claude')
    registry.set_agent_provider(a, 'kong')
    assert.equals('kong', a.provider)
  end)

  it('clears _cached_system on provider switch', function()
    local a = agent.new('switcher', '', 'default', 'none', 'claude')
    a._cached_system = 'old system prompt'
    registry.set_agent_provider(a, 'kong')
    assert.is_nil(a._cached_system)
  end)
end)
