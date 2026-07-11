local M = {}

-- Default config
local defaults = {
  default_profile = 'default',
  default_context_mode = 'project',
}

M._config = {}

function M.setup(config)
  assert(type(config) == 'table' or config == nil, 'thorny.setup() expects a table')
  M._config = vim.tbl_deep_extend('force', defaults, config or {})
end

return M
