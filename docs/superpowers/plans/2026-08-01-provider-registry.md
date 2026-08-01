# Provider Registry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make thorny's provider pluggable — each agent picks its provider by name, switchable on the fly via `:ThornyProvider`, with Claude registered as the default.

**Architecture:** A new `ProviderRegistry` module (keyed by name) stores provider modules. `chat.lua` looks up the provider from the registry using `a.provider` instead of receiving it as a hardcoded parameter. Built-in Claude provider is registered in `setup()`; third-party plugins call `require('thorny').register_provider(name, mod)`.

**Tech Stack:** Pure Lua, Neovim APIs, Telescope (for picker)

## Global Constraints

- Lua 5.1 (LuaJIT as shipped with Neovim ≥ 0.9)
- No new runtime dependencies — pure Lua + Neovim stdlib + Telescope only
- No test execution steps — test runner hangs in the subagent environment; write tests but do not run them
- Follow existing patterns exactly: provider registry mirrors `lua/thorny/tools/registry.lua`; picker mirrors `pick_profile` in `lua/thorny/ui/picker.lua`

---

## File Map

**Create:**
- `lua/thorny/provider/registry.lua` — `register`, `get`, `list_names`
- `tests/thorny/provider/registry_spec.lua` — unit tests for provider registry

**Modify:**
- `lua/thorny/agent.lua` — add `provider` field to `M.new()`
- `lua/thorny/registry.lua` — add `set_agent_provider`
- `lua/thorny/ui/chat.lua` — remove `provider_mod` param; look up from provider registry
- `lua/thorny/ui/picker.lua` — add `pick_provider`
- `lua/thorny/init.lua` — register Claude; add `default_provider` config; add `:ThornyProvider` command; expose `M.register_provider`
- `tests/thorny/agent_spec.lua` — add provider field test
- `tests/thorny/registry_spec.lua` — add `set_agent_provider` test

---

## Task 1: Provider registry module

**Files:**
- Create: `lua/thorny/provider/registry.lua`
- Create: `tests/thorny/provider/registry_spec.lua`

**Interfaces:**
- Produces:
  - `M.register(name, mod)` — stores provider module; idempotent by name
  - `M.get(name)` → `table | nil` — returns provider module or nil
  - `M.list_names()` → `string[]` — sorted array of registered provider names
  - `M.reset()` — clears all registrations (for tests)

- [ ] **Step 1: Create `lua/thorny/provider/registry.lua`**

```lua
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
```

- [ ] **Step 2: Create `tests/thorny/provider/registry_spec.lua`**

```lua
local provider_registry = require('thorny.provider.registry')

local fake_provider = { stream = function() end }

describe('provider registry', function()
  before_each(function()
    provider_registry.reset()
  end)

  it('registers and retrieves a provider by name', function()
    provider_registry.register('claude', fake_provider)
    assert.equals(fake_provider, provider_registry.get('claude'))
  end)

  it('get returns nil for unknown provider', function()
    assert.is_nil(provider_registry.get('unknown'))
  end)

  it('list_names returns sorted names', function()
    provider_registry.register('kong', fake_provider)
    provider_registry.register('claude', fake_provider)
    local names = provider_registry.list_names()
    assert.same({ 'claude', 'kong' }, names)
  end)

  it('register is idempotent — overwrites on re-registration', function()
    local mod_a = { stream = function() end }
    local mod_b = { stream = function() end }
    provider_registry.register('claude', mod_a)
    provider_registry.register('claude', mod_b)
    assert.equals(mod_b, provider_registry.get('claude'))
  end)

  it('register errors on missing stream function', function()
    assert.has_error(function()
      provider_registry.register('bad', {})
    end)
  end)
end)
```

- [ ] **Step 3: Commit**

```bash
git add lua/thorny/provider/registry.lua tests/thorny/provider/registry_spec.lua
git commit -m "feat: add provider registry module"
```

---

## Task 2: Add `provider` field to agent; add `set_agent_provider` to registry

**Files:**
- Modify: `lua/thorny/agent.lua`
- Modify: `lua/thorny/registry.lua`
- Modify: `tests/thorny/agent_spec.lua`
- Modify: `tests/thorny/registry_spec.lua`

**Interfaces:**
- Consumes: nothing new
- Produces:
  - `agent.new(name, persona, profile, context_mode, provider)` — `provider` defaults to `'claude'`
  - `agent.provider` field on all agent tables
  - `registry.set_agent_provider(a, provider_name)` — sets `a.provider` and clears `a._cached_system`

- [ ] **Step 1: Add `provider` field to `lua/thorny/agent.lua`**

Replace the existing `M.new` function:

```lua
function M.new(name, persona, profile, context_mode, provider)
  assert(type(name) == 'string' and name ~= '', 'agent name must be a non-empty string')
  return {
    name           = name,
    persona        = persona or '',
    profile        = profile or 'default',
    context_mode   = context_mode or 'project',
    provider       = provider or 'claude',
    history        = {},
    pending_edits  = {},
    buf            = nil,
    _cached_system = nil,
  }
end
```

- [ ] **Step 2: Add `set_agent_provider` to `lua/thorny/registry.lua`**

Add after the existing `set_agent_profile` function:

```lua
function M.set_agent_provider(a, provider_name)
  a.provider = provider_name
  a._cached_system = nil  -- force rebuild; different providers may format differently
end
```

- [ ] **Step 3: Add provider field test to `tests/thorny/agent_spec.lua`**

Add inside the existing `describe('agent.new()')` block:

```lua
  it('defaults provider to claude when nil', function()
    local a = agent.new('test', 'persona', 'personal', 'project', nil)
    assert.equals('claude', a.provider)
  end)

  it('accepts explicit provider name', function()
    local a = agent.new('test', 'persona', 'personal', 'project', 'kong')
    assert.equals('kong', a.provider)
  end)
```

- [ ] **Step 4: Add `set_agent_provider` test to `tests/thorny/registry_spec.lua`**

Add a new describe block at the bottom of the file:

```lua
describe('registry set_agent_provider', function()
  before_each(function()
    registry.setup({
      default = { api_key = 'sk-ant-test' },
    })
  end)

  it('switches the provider field on the agent', function()
    local a = agent.new('switcher', '', 'default', 'none', 'claude')
    registry.set_agent_provider(a, 'kong')
    assert.equals('kong', a.provider)
  end)

  it('clears _cached_system on provider switch', function()
    local a = agent.new('switcher', '', 'default', 'none', 'claude')
    a._cached_system = 'old system prompt'
    registry.set_agent_provider(a, 'kong')
    assert.is_nil(a._cached_system)
  end)
end)
```

- [ ] **Step 5: Commit**

```bash
git add lua/thorny/agent.lua lua/thorny/registry.lua tests/thorny/agent_spec.lua tests/thorny/registry_spec.lua
git commit -m "feat: add provider field to agent; add set_agent_provider to registry"
```

---

## Task 3: Wire `chat.lua` to provider registry

**Files:**
- Modify: `lua/thorny/ui/chat.lua`

**Interfaces:**
- Consumes:
  - `require('thorny.provider.registry').get(name)` → `table | nil`
  - `a.provider` — string name set on the agent
- Changes:
  - `M.open(a, registry, context_mod)` — drop `provider_mod` parameter
  - `send_message(a, registry, context_mod)` — drop `provider_mod` parameter; look up provider inline
  - All internal `provider_mod.stream(...)` calls unchanged — just sourced from registry now

- [ ] **Step 1: Add provider registry require and update `send_message` signature**

At the top of `lua/thorny/ui/chat.lua`, add:

```lua
local provider_registry = require('thorny.provider.registry')
```

Change the `send_message` function signature from:
```lua
local function send_message(a, registry, context_mod, provider_mod)
```
to:
```lua
local function send_message(a, registry, context_mod)
```

At the start of `send_message`, after `if input == '' then return end`, add the provider lookup:

```lua
  local provider_mod = provider_registry.get(a.provider or 'claude')
  if not provider_mod then
    local msg = 'provider "' .. (a.provider or 'claude') .. '" is not registered'
    append_history(a.buf, { '', '[thorny error] ' .. msg, '' })
    vim.notify('thorny: ' .. msg, vim.log.levels.ERROR)
    return
  end
```

- [ ] **Step 2: Update `M.open` signature**

Change:
```lua
function M.open(a, registry, context_mod, provider_mod)
```
to:
```lua
function M.open(a, registry, context_mod)
```

Update the `<CR>` keymap call inside `M.open` from:
```lua
  vim.keymap.set('n', '<CR>', function()
    send_message(a, registry, context_mod, provider_mod)
  end, opts)
```
to:
```lua
  vim.keymap.set('n', '<CR>', function()
    send_message(a, registry, context_mod)
  end, opts)
```

- [ ] **Step 3: Remove stale `mock_provider` arg from `tests/thorny/ui/chat_spec.lua`**

The test file passes a 4th `mock_provider` argument to `chat.open()` that is now unused. Remove it from all four call sites:

```lua
-- before
chat.open(a, mock_registry, mock_context, mock_provider)
-- after
chat.open(a, mock_registry, mock_context)
```

Also remove the `local mock_provider = { stream = function() end }` line from each `it` block that declared it.

- [ ] **Step 4: Commit**

```bash
git add lua/thorny/ui/chat.lua tests/thorny/ui/chat_spec.lua
git commit -m "refactor: chat.lua looks up provider from registry; remove hardcoded provider_mod param"
```

---

## Task 4: Add `pick_provider` to picker

**Files:**
- Modify: `lua/thorny/ui/picker.lua`

**Interfaces:**
- Consumes: `provider_registry.list_names()` → `string[]`
- Produces: `M.pick_provider(provider_registry, on_select)` — Telescope picker; calls `on_select(name)` with the chosen provider name string

- [ ] **Step 1: Add `pick_provider` to `lua/thorny/ui/picker.lua`**

Add before `return M`:

```lua
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
```

- [ ] **Step 2: Commit**

```bash
git add lua/thorny/ui/picker.lua
git commit -m "feat: add pick_provider Telescope picker"
```

---

## Task 5: Wire `init.lua` — register Claude, `:ThornyProvider`, public API

**Files:**
- Modify: `lua/thorny/init.lua`

**Interfaces:**
- Consumes:
  - `require('thorny.provider.registry')` — `.register(name, mod)`, `.list_names()`
  - `require('thorny.provider.claude')` — existing Claude provider
  - `registry().set_agent_provider(a, name)` — from Task 2
  - `picker().pick_provider(provider_reg, cb)` — from Task 4
- Produces:
  - `M.register_provider(name, mod)` — public API for third-party plugins
  - `default_provider` config key (default: `'claude'`)
  - `:ThornyProvider` command — switches current agent's provider via picker

- [ ] **Step 1: Add `default_provider` to defaults and register Claude in `setup()`**

In `lua/thorny/init.lua`, add `default_provider = 'claude'` to the defaults table:

```lua
local defaults = {
  default_profile      = 'default',
  default_context_mode = 'project',
  default_provider     = 'claude',
  profiles_path        = vim.fn.expand('~/.config/nvim/thorny/profiles.json'),
  persist_path         = vim.fn.expand('~/.local/share/nvim/thorny'),
}
```

At the bottom of `M.setup()`, just before the global keymaps block, add:

```lua
  -- Register built-in providers. Claude is the default.
  local provider_registry = require('thorny.provider.registry')
  provider_registry.register('claude', require('thorny.provider.claude'))
```

- [ ] **Step 2: Update `ThornyNew` to pass `default_provider`**

Change the `ThornyNew` command handler from:
```lua
    local a = agent_mod().new(name, '', M._config.default_profile, M._config.default_context_mode)
```
to:
```lua
    local a = agent_mod().new(name, '', M._config.default_profile, M._config.default_context_mode, M._config.default_provider)
```

- [ ] **Step 3: Update `chat().open()` calls to drop the `claude()` argument**

Change both occurrences of `chat().open(a, registry(), context(), claude())` to:
```lua
chat().open(a, registry(), context())
```

(There are two: one in `ThornyNew` and one in `ThornySwitch`.)

- [ ] **Step 4: Add `:ThornyProvider` command**

Add after the existing `:ThornyProfile` command block:

```lua
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
```

- [ ] **Step 5: Expose `M.register_provider` public API**

Add after `M.register_tool`:

```lua
-- Public API for third-party plugins.
-- Call from your plugin's setup() after require('thorny').setup() has run.
--
-- Example:
--   require('thorny').register_provider('kong', require('thorny-kong.provider'))
function M.register_provider(name, mod)
  require('thorny.provider.registry').register(name, mod)
end
```

- [ ] **Step 6: Remove the now-unused `claude` lazy loader**

Remove this line from the lazy-loaded modules block at the top of `init.lua`:
```lua
local function claude()    return require('thorny.provider.claude') end
```

- [ ] **Step 7: Commit**

```bash
git add lua/thorny/init.lua
git commit -m "feat: register Claude provider in setup(); add :ThornyProvider command and register_provider API"
```
