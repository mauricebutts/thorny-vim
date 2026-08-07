local M = {}

local _tools = {}  -- { [name] = spec }
local _order = {}  -- insertion order, for stable get_definitions()

function M.register(spec)
  assert(type(spec) == 'table',              'tool spec must be a table')
  assert(type(spec.definition) == 'table',   'spec.definition is required')
  assert(type(spec.definition.name) == 'string', 'spec.definition.name must be a string')
  local name = spec.definition.name
  if not _tools[name] then
    table.insert(_order, name)
  end
  _tools[name] = spec
end

-- Returns canonical tool definitions. No provider-specific additions.
function M.get_definitions()
  local defs = {}
  for _, name in ipairs(_order) do
    table.insert(defs, vim.deepcopy(_tools[name].definition))
  end
  return defs
end

function M.get(name)
  return _tools[name]
end

-- Clears all registrations — intended for tests / hot-reload
function M.reset()
  _tools = {}
  _order = {}
end

return M
