local registry = require('thorny.tools.registry')

describe('tools.registry', function()
  before_each(function()
    registry.reset()
  end)

  describe('get_definitions()', function()
    it('returns the definition with parameters key intact', function()
      registry.register({
        definition = {
          name        = 'TestTool',
          description = 'A test tool.',
          parameters  = {
            type       = 'object',
            properties = { path = { type = 'string' } },
            required   = { 'path' },
          },
        },
        mode    = 'auto',
        execute = function() return 'ok' end,
      })

      local defs = registry.get_definitions()
      assert.equals(1, #defs)
      assert.equals('TestTool', defs[1].name)
      assert.is_not_nil(defs[1].parameters)
      assert.is_nil(defs[1].input_schema)
    end)

    it('does not add cache_control to any definition', function()
      for _, tname in ipairs({ 'ToolA', 'ToolB', 'ToolC' }) do
        registry.register({
          definition = {
            name        = tname,
            description = 'desc',
            parameters  = { type = 'object', properties = {}, required = {} },
          },
          mode    = 'auto',
          execute = function() return '' end,
        })
      end

      for _, def in ipairs(registry.get_definitions()) do
        assert.is_nil(def.cache_control)
      end
    end)

    it('passes server tool definitions through unchanged', function()
      registry.register({
        definition = { type = 'web_search_20260318', name = 'web_search' },
        mode       = 'server',
      })

      local defs = registry.get_definitions()
      assert.equals(1, #defs)
      assert.equals('web_search_20260318', defs[1].type)
      assert.equals('web_search', defs[1].name)
    end)

    it('returns definitions in registration order', function()
      for _, tname in ipairs({ 'First', 'Second', 'Third' }) do
        registry.register({
          definition = {
            name        = tname,
            description = '',
            parameters  = { type = 'object', properties = {}, required = {} },
          },
          mode    = 'auto',
          execute = function() return '' end,
        })
      end

      local defs = registry.get_definitions()
      assert.equals('First',  defs[1].name)
      assert.equals('Second', defs[2].name)
      assert.equals('Third',  defs[3].name)
    end)
  end)
end)
