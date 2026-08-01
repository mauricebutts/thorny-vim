local M = {}

local _providers = {}  -- { [name] = mod }

function M.register(name, mod)
  assert(type(name) == 'string' and name ~= '', 'provider name must be a non-empty string')
  assert(type(mod) == 'table',                  'provider must be a table')
  assert(type(mod.stream) == 'function',         'provider must implement stream()')
  _providers[name] = mod
end

function M.get(name)
  return _providers[name]
end

function M.list_names()
  local names = {}
  for name in pairs(_providers) do
    table.insert(names, name)
  end
  table.sort(names)
  return names
end

function M.reset()
  _providers = {}
end

return M
