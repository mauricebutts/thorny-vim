local provider_registry = require('thorny.provider.registry')

local fake_provider = { stream = function() end }

describe('provider registry', function()
  before_each(function()
    provider_registry.reset()
  end)

  it('registers and retrieves a provider by name', function()
    provider_registry.register('claude', fake_provider)
    assert.equals(fake_provider, provider_registry.get('claude'))
  end)

  it('get returns nil for unknown provider', function()
    assert.is_nil(provider_registry.get('unknown'))
  end)

  it('list_names returns sorted names', function()
    provider_registry.register('kong', fake_provider)
    provider_registry.register('claude', fake_provider)
    local names = provider_registry.list_names()
    assert.same({ 'claude', 'kong' }, names)
  end)

  it('register is idempotent — overwrites on re-registration', function()
    local mod_a = { stream = function() end }
    local mod_b = { stream = function() end }
    provider_registry.register('claude', mod_a)
    provider_registry.register('claude', mod_b)
    assert.equals(mod_b, provider_registry.get('claude'))
  end)

  it('register errors on missing stream function', function()
    assert.has_error(function()
      provider_registry.register('bad', {})
    end)
  end)
end)
