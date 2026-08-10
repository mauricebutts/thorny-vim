# Provider-Agnostic Tools Design

**Date:** 2026-08-03
**Status:** Approved

## Overview

Refactor thorny's tool system so that tool definitions use a canonical thorny-defined schema, and providers are responsible for translating that schema into whatever format their API requires. This enables tools — both built-in and plugin-provided — to work across all providers (Claude, OpenAI, Kong, future providers) without modification.

## Goals

- Tools are defined once in a neutral format; no provider-specific knowledge required
- Providers own the translation from canonical → their API format
- Plugin authors can register tools and providers using the same patterns as built-ins
- Existing tool behavior (auto, pending, server modes) is unchanged

## Canonical Tool Schema

All `auto` and `pending` tools use this format:

```lua
{
  definition = {
    name        = 'ReadFile',
    description = 'Read the full contents of a file.',
    parameters  = {
      type       = 'object',
      properties = {
        file_path = { type = 'string', description = 'Path to the file' },
      },
      required = { 'file_path' },
    },
  },
  mode    = 'auto',   -- auto | pending | server
  execute = function(input, ctx) ... end,
}
```

The only change from the current format is `input_schema` → `parameters`. The `execute` function and `mode` field are unchanged and remain provider-agnostic.

### Server Tools

Server tools (e.g. `web_search`) are provider-specific — they represent infrastructure that a specific provider executes, with no canonical equivalent. They remain in the tool registry but keep their native provider format in `definition`. Providers identify them by the presence of a `type` field (e.g. `type = 'web_search_20260318'`) and pass them through untranslated or skip them depending on whether they support that server tool.

```lua
-- server tool: stays in native format, no parameters field
{
  definition = {
    type = 'web_search_20260318',
    name = 'web_search',
  },
  mode = 'server',
  -- no execute function: provider infrastructure handles it
}
```

## Tool Registry Changes

`registry.get_definitions()` currently adds Anthropic-specific `cache_control` to the last non-server tool. That logic is Anthropic-specific and moves into the Claude provider's translation step. The registry returns clean canonical definitions with no provider additions:

```lua
function M.get_definitions()
  local defs = {}
  for _, name in ipairs(_order) do
    table.insert(defs, vim.deepcopy(_tools[name].definition))
  end
  return defs  -- no cache_control, no provider-specific additions
end
```

No other changes to the registry. The `register`, `get`, `reset` functions are unchanged. The public API `require('thorny').register_tool(spec)` is unchanged.

## Updated Provider Contract

`provider/init.lua` is updated to document the translation responsibility and the two previously-undocumented callbacks:

```lua
-- stream(messages, system, tools, profile, callbacks)
--   messages  : {role, content}[]
--   system    : string
--   tools     : thorny canonical tool definitions
--               Provider must translate these to its API format before use.
--               Server tools (definition.type present) may be passed through
--               as-is or skipped depending on provider support.
--   profile   : provider-specific credentials table
--   callbacks : {
--     on_token     : function(text)
--     on_tool_use  : function({id, name, input})
--     on_tools_done: function(content_blocks)
--     on_pause     : function(content_blocks)   -- server tool executing; optional
--     on_done      : function()
--     on_error     : function(msg)
--   }
```

`on_pause` is optional — providers without server tools never fire it. Providers that support client-side tools must fire `on_tools_done` when a tool-use turn completes.

## Provider-Side Translation

Each provider owns a local `translate_tools(defs)` function. It receives canonical definitions from the registry and returns the provider-specific array to embed in the API request body.

### Claude provider

```lua
local function translate_tools(defs)
  local out = {}
  for _, def in ipairs(defs) do
    if def.type then
      -- server tool: already in native Anthropic format, pass through
      table.insert(out, def)
    else
      -- canonical tool: rename parameters → input_schema
      table.insert(out, {
        name         = def.name,
        description  = def.description,
        input_schema = def.parameters,
      })
    end
  end
  -- Anthropic prompt caching: mark last non-server tool
  for i = #out, 1, -1 do
    if not out[i].type then
      out[i].cache_control = { type = 'ephemeral' }
      break
    end
  end
  return out
end
```

Inside `stream()`:
```lua
tools = translate_tools(tools or registry.get_definitions()),
```

### OpenAI provider (illustrative)

```lua
local function translate_tools(defs)
  local out = {}
  for _, def in ipairs(defs) do
    if not def.type then  -- skip server tools; OpenAI has no equivalent
      table.insert(out, {
        type = 'function',
        ['function'] = {
          name        = def.name,
          description = def.description,
          parameters  = def.parameters,
        },
      })
    end
  end
  return out
end
```

### Kong provider (illustrative)

Same pattern — Kong's `translate_tools()` emits whatever format the Kong AI Gateway API requires, filtering or transforming as needed.

## Plugin Authoring

A plugin like `thorny-kong.nvim` registers tools and a provider using the same public API as built-ins:

```lua
-- thorny-kong.nvim/lua/thorny-kong/init.lua
local function setup()
  local thorny = require('thorny')
  thorny.register_tool(require('thorny-kong.tools.list_services'))
  thorny.register_tool(require('thorny-kong.tools.get_route'))
  thorny.register_provider('kong', require('thorny-kong.provider'))
end
```

Plugin tools use the canonical schema — they have no knowledge of which provider will execute them:

```lua
-- thorny-kong.nvim/lua/thorny-kong/tools/list_services.lua
return {
  definition = {
    name        = 'ListKongServices',
    description = 'List all services registered in the Kong gateway.',
    parameters  = {
      type       = 'object',
      properties = {
        workspace = { type = 'string', description = 'Kong workspace name' },
      },
      required   = {},
    },
  },
  mode    = 'auto',
  execute = function(input, ctx)
    -- curl Kong admin API, return result string
  end,
}
```

The Kong provider's `translate_tools()` handles converting these to Kong's format, just as the Claude provider handles converting built-in tools to Anthropic's format.

## Files Changed

### thorny (core)

| File | Change |
|---|---|
| `lua/thorny/tools/registry.lua` | Remove `cache_control` logic from `get_definitions()` |
| `lua/thorny/tools/builtin/*.lua` | Rename `input_schema` → `parameters` in all 4 canonical tools (not web_search) |
| `lua/thorny/provider/init.lua` | Update contract documentation |
| `lua/thorny/provider/claude.lua` | Add `translate_tools()`, move `cache_control` logic here, call it in `stream()` |

### thorny-kong.nvim (plugin — future)

| File | Description |
|---|---|
| `lua/thorny-kong/provider.lua` | Kong provider with `stream()` and `translate_tools()` |
| `lua/thorny-kong/tools/*.lua` | Kong-specific tools in canonical schema |
| `lua/thorny-kong/init.lua` | `setup()` registers all tools and the provider |

## What Does Not Change

- Tool `mode` values (`auto`, `pending`, `server`) and their semantics
- The `execute(input, ctx)` function signature
- `chat.lua` — no changes needed; it calls `provider.stream()` with canonical defs already
- `require('thorny').register_tool()` and `require('thorny').register_provider()` public API
- How `on_tool_use`, `on_tools_done`, and `on_pause` work in `chat.lua`
