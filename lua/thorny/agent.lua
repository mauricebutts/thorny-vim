local M = {}

function M.new(name, persona, profile, context_mode)
  assert(type(name) == 'string' and name ~= '', 'agent name must be a non-empty string')
  return {
    name         = name,
    persona      = persona or '',
    profile      = profile or 'default',
    context_mode = context_mode or 'project',
    history      = {},
    pending_edits = {},
    buf          = nil,
  }
end

function M.add_message(a, role, content)
  table.insert(a.history, { role = role, content = content })
end

-- Appends a tool_result in the Anthropic API format (role=user, content=[{type=tool_result,...}])
function M.add_tool_result(a, tool_use_id, content)
  table.insert(a.history, {
    role = 'user',
    content = {
      {
        type        = 'tool_result',
        tool_use_id = tool_use_id,
        content     = content,
      }
    }
  })
end

function M.add_pending_edit(a, tool_call)
  table.insert(a.pending_edits, tool_call)
end

function M.pop_pending_edit(a)
  if #a.pending_edits == 0 then return nil end
  return table.remove(a.pending_edits) -- removes and returns last element
end

return M
