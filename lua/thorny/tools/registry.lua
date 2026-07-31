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

-- Returns the definitions array sent to the Claude API.
-- Attaches cache_control to the last non-server tool so the tools list is
-- cached by Anthropic's prompt-caching layer.
function M.get_definitions()
  local defs = {}
  for _, name in ipairs(_order) do
    table.insert(defs, vim.deepcopy(_tools[name].definition))
  end
  -- Walk backwards to find the last non-server tool and mark it for caching
  for i = #_order, 1, -1 do
    if _tools[_order[i]].mode ~= 'server' then
      defs[i].cache_control = { type = 'ephemeral' }
      break
    end
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
