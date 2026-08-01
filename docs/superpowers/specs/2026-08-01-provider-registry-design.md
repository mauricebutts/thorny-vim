# Provider Registry

**Date:** 2026-08-01
**Status:** Approved

## Goal

Make thorny's provider pluggable. Each agent independently picks its provider (e.g. `'claude'`, `'kong'`), switchable on the fly via `:ThornyProvider`. Third-party plugins register providers via `require('thorny').register_provider(name, mod)`.

## Motivation

thorny currently hardcodes Claude as the only provider. The Kong AI Gateway plugin (`thorny-kong.nvim`) needs a clean hook-in point. The same mechanism will serve any future provider (OpenAI, local models, etc.).

## Design

### Provider contract

A provider is a table with a single required function:

```lua
provider.stream(messages, system, tools, profile, callbacks)
```

This is the existing interface already documented in `lua/thorny/provider/init.lua`. No changes to the contract.

### `lua/thorny/provider/registry.lua` (new)

```lua
M.register(name, mod)   -- idempotent; overwrites on re-registration
M.get(name)             -- returns provider module or nil
M.list_names()          -- returns sorted array of registered names
```

Mirrors `lua/thorny/tools/registry.lua` in shape.

### Agent model (`lua/thorny/agent.lua`)

Add `provider` field to `M.new()`:

```lua
function M.new(name, persona, profile, context_mode, provider)
  return {
    ...
    provider = provider or 'claude',
  }
end
```

### Agent registry (`lua/thorny/registry.lua`)

Add:

```lua
function M.set_agent_provider(a, provider_name)
  a.provider = provider_name
  a._cached_system = nil  -- force rebuild; different providers may format differently
end
```

### `lua/thorny/ui/chat.lua`

- Remove `provider_mod` parameter from `M.open(a, registry, context_mod)` and `send_message`
- Look up provider inline: `local provider_mod = provider_registry.get(a.provider)`
- Error gracefully if provider not registered: append error to buffer, return early
- `on_tools_done` and `on_pause` re-send calls use the same looked-up `provider_mod`

### `lua/thorny/ui/picker.lua`

Add `pick_provider(provider_registry, callback)` — Telescope picker over `provider_registry.list_names()`. Mirrors `pick_profile`.

### `lua/thorny/init.lua`

- Add `default_provider = 'claude'` to defaults
- In `setup()`:
  - Register Claude: `provider_registry.register('claude', require('thorny.provider.claude'))`
  - Update `ThornyNew` to pass `M._config.default_provider` to `agent_mod.new()`
  - Update `chat().open()` call — drop the `claude()` argument
  - Add `:ThornyProvider` command (mirrors `:ThornyProfile`)
- Expose public API:
  ```lua
  function M.register_provider(name, mod)
    require('thorny.provider.registry').register(name, mod)
  end
  ```

## Error handling

If `provider_registry.get(a.provider)` returns nil (provider not registered), `send_message` appends `[thorny error] provider '<name>' is not registered` to the buffer and returns without calling the API.

## What's not changing

- The `stream()` contract — providers implement the same interface as today
- Profiles — credentials stay in `profiles.json`, independent of provider
- Tool registry — tools remain provider-agnostic

## Kong plugin usage (after this lands)

```lua
-- in thorny-kong.nvim's setup():
require('thorny').register_provider('kong', require('thorny-kong.provider'))
```
