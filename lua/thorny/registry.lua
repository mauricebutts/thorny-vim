local M = {}

local _agents   = {}  -- name -> agent
local _profiles = {}  -- name -> {api_key}

function M.setup(profiles_map)
  _agents   = {}
  _profiles = profiles_map or {}
end

function M.add_agent(a)
  _agents[a.name] = a
  return a
end

function M.get_agent(name)
  return _agents[name]
end

function M.list_agents()
  local result = {}
  for _, a in pairs(_agents) do
    table.insert(result, a)
  end
  return result
end

function M.remove_agent(name)
  _agents[name] = nil
end

function M.get_profile(name)
  return _profiles[name]
end

function M.list_profiles()
  local result = {}
  for name, p in pairs(_profiles) do
    local entry = vim.tbl_extend('force', p, { name = name })
    table.insert(result, entry)
  end
  return result
end

function M.set_agent_profile(a, profile_name)
  a.profile = profile_name
  a._cached_system = nil
  local p = _profiles[profile_name]
  if p and p.provider then
    a.provider = p.provider
  end
end

return M
