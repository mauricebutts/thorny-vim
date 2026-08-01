local pickers    = require('telescope.pickers')
local finders    = require('telescope.finders')
local conf       = require('telescope.config').values
local actions    = require('telescope.actions')
local action_st  = require('telescope.actions.state')

local M = {}

function M.pick_agent(registry, on_select)
  local agents = registry.list_agents()
  if #agents == 0 then
    vim.notify('thorny: no active agents', vim.log.levels.INFO)
    return
  end
  pickers.new({}, {
    prompt_title = 'Thorny Agents',
    finder = finders.new_table({
      results = agents,
      entry_maker = function(a)
        return {
          value   = a,
          display = a.name .. '  [' .. a.profile .. '] [' .. a.context_mode .. ']',
          ordinal = a.name,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local entry = action_st.get_selected_entry()
        if entry then on_select(entry.value) end
      end)
      return true
    end,
  }):find()
end

function M.pick_profile(registry, on_select)
  local profiles = registry.list_profiles()
  if #profiles == 0 then
    vim.notify('thorny: no profiles configured', vim.log.levels.INFO)
    return
  end
  pickers.new({}, {
    prompt_title = 'Thorny Profiles',
    finder = finders.new_table({
      results = profiles,
      entry_maker = function(p)
        return {
          value   = p,
          display = p.name,
          ordinal = p.name,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local entry = action_st.get_selected_entry()
        if entry then on_select(entry.value) end
      end)
      return true
    end,
  }):find()
end

function M.pick_context_files(cwd, on_select)
  local context = require('thorny.context')
  local files = context.get_file_tree(cwd)
  pickers.new({}, {
    prompt_title = 'Pin Context Files',
    finder = finders.new_table({
      results = files,
      entry_maker = function(f)
        return { value = f, display = f, ordinal = f }
      end,
    }),
    sorter = conf.file_sorter({}),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local entry = action_st.get_selected_entry()
        if entry then on_select(entry.value) end
      end)
      return true
    end,
  }):find()
end

function M.pick_provider(provider_reg, on_select)
  local names = provider_reg.list_names()
  if #names == 0 then
    vim.notify('thorny: no providers registered', vim.log.levels.INFO)
    return
  end
  pickers.new({}, {
    prompt_title = 'Thorny Providers',
    finder = finders.new_table({
      results = names,
      entry_maker = function(name)
        return { value = name, display = name, ordinal = name }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local entry = action_st.get_selected_entry()
        if entry then on_select(entry.value) end
      end)
      return true
    end,
  }):find()
end

return M
