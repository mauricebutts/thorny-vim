-- Provider interface — all providers must implement stream().
--
-- stream(messages, system, tools, profile, callbacks)
--   messages  : {role, content}[]   -- conversation history
--   system    : string              -- system prompt (with context prepended)
--   tools     : table[]             -- Anthropic tool definitions
--   profile   : {api_key}           -- credentials
--   callbacks : {
--     on_token    : function(text)
--     on_tool_use : function({id, name, input})
--     on_done     : function()
--     on_error    : function(msg)
--   }

return {}
