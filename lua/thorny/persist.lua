local agent_mod = require('thorny.agent')
local M = {}

M._dir = vim.fn.expand('~/.local/share/nvim/thorny')

local function agent_path(name)
  return M._dir .. '/' .. name .. '.json'
end

function M.save_agent(a)
  vim.fn.mkdir(M._dir, 'p')
  local data = vim.json.encode({
    name         = a.name,
    persona      = a.persona,
    profile      = a.profile,
    context_mode = a.context_mode,
    history      = a.history,
  })
  vim.fn.writefile({ data }, agent_path(a.name))
end

function M.load_agent(name)
  local path = agent_path(name)
  if vim.fn.filereadable(path) == 0 then return nil end
  local lines = vim.fn.readfile(path)
  local ok, data = pcall(vim.json.decode, table.concat(lines, ''))
  if not ok then return nil end
  local a = agent_mod.new(data.name, data.persona, data.profile, data.context_mode)
  a.history = data.history or {}
  return a
end

function M.load_all_agents()
  local result = {}
  local files = vim.fn.glob(M._dir .. '/*.json', false, true)
  for _, f in ipairs(files) do
    -- skip profiles.json if it ends up here
    local name = vim.fn.fnamemodify(f, ':t:r')
    local a = M.load_agent(name)
    if a then table.insert(result, a) end
  end
  return result
end

function M.load_profiles(path)
  path = path or vim.fn.expand('~/.config/nvim/thorny/profiles.json')
  if vim.fn.filereadable(path) == 0 then return {} end
  local lines = vim.fn.readfile(path)
  local ok, data = pcall(vim.json.decode, table.concat(lines, ''))
  if not ok then return {} end
  return data
end

return M
