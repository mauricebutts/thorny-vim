local M = {}

local defaults = {
  default_profile      = 'default',
  default_context_mode = 'project',
  default_provider     = 'claude',
  profiles_path        = vim.fn.expand('~/.config/nvim/thorny/profiles.json'),
  persist_path         = vim.fn.expand('~/.local/share/nvim/thorny'),
}

M._config = {}

-- Lazy-loaded modules (avoids loading telescope at startup)
local function registry()  return require('thorny.registry') end
local function persist()   return require('thorny.persist')  end
local function agent_mod() return require('thorny.agent')    end
local function chat()      return require('thorny.ui.chat')  end
local function picker()    return require('thorny.ui.picker') end
local function context()   return require('thorny.context')  end

function M.setup(config)
  assert(type(config) == 'table' or config == nil, 'thorny.setup() expects a table')
  M._config = vim.tbl_deep_extend('force', defaults, config or {})

  -- Load profiles and seed registry
  local p = persist()
  p._dir = M._config.persist_path
  local profiles = p.load_profiles(M._config.profiles_path)
  registry().setup(profiles)

  -- Warn if profiles file is world-readable
  local pf = M._config.profiles_path
  if vim.fn.filereadable(pf) == 1 then
    local perms = vim.fn.getfperm(pf)
    if perms:sub(7, 9) ~= '---' then
      vim.notify(
        'thorny: ' .. pf .. ' is world-readable. Run: chmod 600 ' .. pf,
        vim.log.levels.WARN
      )
    end
  end

  -- Load persisted agents
  for _, a in ipairs(p.load_all_agents()) do
    registry().add_agent(a)
  end

  -- Register commands
  vim.api.nvim_create_user_command('ThornyNew', function(opts)
    local name = opts.args ~= '' and opts.args or ('agent-' .. tostring(os.time()))
    local a = agent_mod().new(name, '', M._config.default_profile, M._config.default_context_mode, M._config.default_provider)
    registry().add_agent(a)
    chat().open(a, registry(), context())
  end, { nargs = '?' })

  vim.api.nvim_create_user_command('ThornySwitch', function()
    picker().pick_agent(registry(), function(a)
      chat().open(a, registry(), context())
    end)
  end, {})

  vim.api.nvim_create_user_command('ThornyKill', function()
    local bufnr = vim.api.nvim_get_current_buf()
    local name  = vim.api.nvim_buf_get_name(bufnr)
    -- buf name is "[thorny] <agent_name>"
    local agent_name = name:match('%[thorny%] (.+)')
    if agent_name then
      registry().remove_agent(agent_name)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    else
      vim.notify('thorny: not a thorny buffer', vim.log.levels.WARN)
    end
  end, {})

  vim.api.nvim_create_user_command('ThornyPersist', function()
    local p2 = persist()
    for _, a in ipairs(registry().list_agents()) do
      p2.save_agent(a)
    end
    vim.notify('thorny: all agents persisted', vim.log.levels.INFO)
  end, {})

  vim.api.nvim_create_user_command('ThornyReloadProfiles', function()
    local p2 = persist()
    local profiles = p2.load_profiles(M._config.profiles_path)
    registry().setup(profiles)
    local count = 0
    for _ in pairs(profiles) do count = count + 1 end
    if count == 0 then
      vim.notify('thorny: no profiles loaded — check ' .. M._config.profiles_path, vim.log.levels.WARN)
    else
      vim.notify('thorny: loaded ' .. count .. ' profile(s)', vim.log.levels.INFO)
    end
  end, {})

  vim.api.nvim_create_user_command('ThornyProfile', function()
    -- Find the agent for the current buffer
    local bufnr = vim.api.nvim_get_current_buf()
    local name  = vim.api.nvim_buf_get_name(bufnr):match('%[thorny%] (.+)')
    local a = name and registry().get_agent(name)
    if not a then
      vim.notify('thorny: not a thorny buffer', vim.log.levels.WARN)
      return
    end
    picker().pick_profile(registry(), function(p3)
      registry().set_agent_profile(a, p3.name)
      vim.notify('thorny: switched "' .. a.name .. '" to profile "' .. p3.name .. '"', vim.log.levels.INFO)
    end)
  end, {})

  vim.api.nvim_create_user_command('ThornyProvider', function()
    local bufnr = vim.api.nvim_get_current_buf()
    local name  = vim.api.nvim_buf_get_name(bufnr):match('%[thorny%] (.+)')
    local a = name and registry().get_agent(name)
    if not a then
      vim.notify('thorny: not a thorny buffer', vim.log.levels.WARN)
      return
    end
    local provider_registry = require('thorny.provider.registry')
    picker().pick_provider(provider_registry, function(provider_name)
      registry().set_agent_provider(a, provider_name)
      vim.notify('thorny: switched "' .. a.name .. '" to provider "' .. provider_name .. '"', vim.log.levels.INFO)
    end)
  end, {})

  -- Auto-save all agents on Neovim exit
  vim.api.nvim_create_autocmd('VimLeavePre', {
    callback = function()
      local p2 = persist()
      for _, a in ipairs(registry().list_agents()) do
        p2.save_agent(a)
      end
    end,
  })

  -- Register built-in tools. Order matters: cache_control is applied to the
  -- last non-server tool (MultiEdit) by registry.get_definitions().
  local tool_registry = require('thorny.tools.registry')
  tool_registry.register(require('thorny.tools.builtin.web_search'))
  tool_registry.register(require('thorny.tools.builtin.read_file'))
  tool_registry.register(require('thorny.tools.builtin.edit'))
  tool_registry.register(require('thorny.tools.builtin.write'))
  tool_registry.register(require('thorny.tools.builtin.multi_edit'))

  -- Register built-in providers. Claude is the default.
  local provider_registry = require('thorny.provider.registry')
  provider_registry.register('claude', require('thorny.provider.claude'))

  -- Global keymaps (non-buffer-local)
  vim.keymap.set('n', '<leader>an', ':ThornyNew<CR>',    { noremap = true, silent = true, desc = 'Thorny: new agent' })
  vim.keymap.set('n', '<leader>as', ':ThornySwitch<CR>', { noremap = true, silent = true, desc = 'Thorny: switch agent' })
  vim.keymap.set('n', '<leader>ak', ':ThornyKill<CR>',   { noremap = true, silent = true, desc = 'Thorny: kill agent' })

  -- Buffer-local keymaps set inside chat.open() for <CR>, <leader>ha, <leader>ac
end

function M.register_tool(spec)
  require('thorny.tools.registry').register(spec)
end

-- Public API for third-party plugins.
-- Call from your plugin's setup() after require('thorny').setup() has run.
--
-- Example:
--   require('thorny').register_provider('kong', require('thorny-kong.provider'))
function M.register_provider(name, mod)
  require('thorny.provider.registry').register(name, mod)
end

return M
