# Tool Registry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace hardcoded tool definitions and dispatch logic with a pluggable registry that third-party plugins can extend via `require('thorny').register_tool(spec)`.

**Architecture:** A central `ToolRegistry` module (keyed by tool name) stores self-contained tool specs — each carrying its Claude API definition plus an execution strategy (`auto` / `pending` / `server`). `claude.lua` queries the registry for the definitions array sent to the API. `chat.lua` queries it for dispatch instead of using an if/elseif chain. Built-ins are pre-registered in `init.lua`; external plugins call `require('thorny').register_tool()` from their own `setup()`.

**Tech Stack:** Pure Lua, Neovim APIs (`vim.fn`, `vim.api`, `vim.json`)

## Global Constraints

- Lua 5.1 (LuaJIT as shipped with Neovim ≥ 0.9)
- No new runtime dependencies — pure Lua + Neovim stdlib only
- `apply_pending_edit` in `chat.lua` must continue to work via `vim.api.nvim_buf_set_lines` (edits live in buffers, not written directly to disk) — do not change to `vim.fn.writefile`
- No test execution steps — test runner hangs in the subagent environment

---

## File Map

**Create:**
- `lua/thorny/tools/registry.lua` — register, get_definitions, get(name), reset
- `lua/thorny/tools/builtin/web_search.lua` — server tool spec (no execute fn)
- `lua/thorny/tools/builtin/read_file.lua` — auto tool spec
- `lua/thorny/tools/builtin/edit.lua` — pending tool spec
- `lua/thorny/tools/builtin/write.lua` — pending tool spec
- `lua/thorny/tools/builtin/multi_edit.lua` — pending tool spec

**Modify:**
- `lua/thorny/provider/claude.lua` — remove hardcoded `TOOLS` / `M.TOOLS`; use `registry.get_definitions()` as default
- `lua/thorny/ui/chat.lua` — wire `on_tools_done` + `apply_pending_edit` to registry dispatch; remove hardcoded tool names
- `lua/thorny/init.lua` — register built-ins in `setup()`; expose `M.register_tool`

---

## Task 1: Registry module

**Files:**
- Create: `lua/thorny/tools/registry.lua`

**Interfaces:**
- Produces:
  - `M.register(spec)` — adds a tool spec; idempotent by name
  - `M.get_definitions()` → `table` — array of definition tables ready for the Claude API; adds `cache_control = { type = 'ephemeral' }` to the last non-server tool
  - `M.get(name)` → `spec | nil`
  - `M.reset()` — clears all registrations (used in future tests)

- [ ] **Step 1: Create `lua/thorny/tools/registry.lua`**

```lua
local M = {}

local _tools = {}  -- { [name] = spec }
local _order = {}  -- insertion order, for stable get_definitions()

function M.register(spec)
  assert(type(spec) == 'table',              'tool spec must be a table')
  assert(type(spec.definition) == 'table',   'spec.definition is required')
  assert(type(spec.definition.name) == 'string', 'spec.definition.name must be a string')
  local name = spec.definition.name
  if not _tools[name] then
    table.insert(_order, name)
  end
  _tools[name] = spec
end

-- Returns the definitions array sent to the Claude API.
-- Attaches cache_control to the last non-server tool so the tools list is
-- cached by Anthropic's prompt-caching layer.
function M.get_definitions()
  local defs = {}
  for _, name in ipairs(_order) do
    table.insert(defs, vim.deepcopy(_tools[name].definition))
  end
  -- Walk backwards to find the last non-server tool and mark it for caching
  for i = #_order, 1, -1 do
    if _tools[_order[i]].mode ~= 'server' then
      defs[i].cache_control = { type = 'ephemeral' }
      break
    end
  end
  return defs
end

function M.get(name)
  return _tools[name]
end

-- Clears all registrations — intended for tests / hot-reload
function M.reset()
  _tools = {}
  _order = {}
end

return M
```

- [ ] **Step 2: Commit**

```bash
git add lua/thorny/tools/registry.lua
git commit -m "feat: add tool registry module"
```

---

## Task 2: Built-in tool specs

**Files:**
- Create: `lua/thorny/tools/builtin/web_search.lua`
- Create: `lua/thorny/tools/builtin/read_file.lua`
- Create: `lua/thorny/tools/builtin/edit.lua`
- Create: `lua/thorny/tools/builtin/write.lua`
- Create: `lua/thorny/tools/builtin/multi_edit.lua`

**Interfaces:**
- Consumes: `require('thorny.context').read_file(abs_path)` → `string | nil`
- Produces: five spec tables, each with `{ definition, mode, execute? }` or `{ definition, mode }` shape

**Notes on pending tool `apply`:** The current `apply_pending_edit` in `chat.lua` edits files through Neovim buffers (`vim.api.nvim_buf_set_lines`) so that the user sees changes highlighted and undo history is preserved. The built-in specs below follow the same approach.

- [ ] **Step 1: Create `lua/thorny/tools/builtin/web_search.lua`**

```lua
-- Server tool: Anthropic executes search on its own infrastructure.
-- No execute function needed — the API handles it.
return {
  definition = {
    type = 'web_search_20260318',
    name = 'web_search',
  },
  mode = 'server',
}
```

- [ ] **Step 2: Create `lua/thorny/tools/builtin/read_file.lua`**

```lua
local context = require('thorny.context')

return {
  definition = {
    name        = 'ReadFile',
    description = 'Read the full contents of a file. Call this before editing a file or answering questions about its contents.',
    input_schema = {
      type       = 'object',
      properties = {
        file_path = { type = 'string', description = 'Path to the file, relative to the project root' },
      },
      required = { 'file_path' },
    },
  },
  mode = 'auto',
  -- execute(input, ctx) → string result sent back as tool_result content
  -- ctx = { cwd = string }
  execute = function(input, ctx)
    local path = input.file_path or ''
    local abs  = path:sub(1, 1) == '/' and path or (ctx.cwd .. '/' .. path)
    local content = context.read_file(abs)
    return content or 'Error: file not found or unreadable'
  end,
}
```

- [ ] **Step 3: Create `lua/thorny/tools/builtin/edit.lua`**

```lua
return {
  definition = {
    name        = 'Edit',
    description = 'Replace exact text in a file. old_string must match exactly (including whitespace).',
    input_schema = {
      type       = 'object',
      properties = {
        file_path  = { type = 'string', description = 'Path to the file to edit' },
        old_string = { type = 'string', description = 'The exact text to replace' },
        new_string = { type = 'string', description = 'The replacement text' },
      },
      required = { 'file_path', 'old_string', 'new_string' },
    },
  },
  mode = 'pending',
}
```

- [ ] **Step 4: Create `lua/thorny/tools/builtin/write.lua`**

```lua
return {
  definition = {
    name        = 'Write',
    description = 'Write complete contents to a file, creating it if it does not exist.',
    input_schema = {
      type       = 'object',
      properties = {
        file_path = { type = 'string', description = 'Path to the file to write' },
        content   = { type = 'string', description = 'The full file contents' },
      },
      required = { 'file_path', 'content' },
    },
  },
  mode = 'pending',
}
```

- [ ] **Step 5: Create `lua/thorny/tools/builtin/multi_edit.lua`**

```lua
return {
  definition = {
    name        = 'MultiEdit',
    description = 'Apply multiple Edit operations to a single file.',
    input_schema = {
      type       = 'object',
      properties = {
        file_path = { type = 'string', description = 'Path to the file to edit' },
        edits     = {
          type  = 'array',
          items = {
            type       = 'object',
            properties = {
              old_string = { type = 'string' },
              new_string = { type = 'string' },
            },
            required = { 'old_string', 'new_string' },
          },
        },
      },
      required = { 'file_path', 'edits' },
    },
  },
  mode = 'pending',
}
```

- [ ] **Step 6: Commit**

```bash
git add lua/thorny/tools/builtin/
git commit -m "feat: add built-in tool specs (web_search, ReadFile, Edit, Write, MultiEdit)"
```

---

## Task 3: Wire `claude.lua` to registry

**Files:**
- Modify: `lua/thorny/provider/claude.lua`

**Interfaces:**
- Consumes: `require('thorny.tools.registry').get_definitions()` → definitions array
- Change: remove the hardcoded `local TOOLS = { ... }` block and `M.TOOLS`; default `tools` parameter to `registry.get_definitions()`

**Note:** The `tools` parameter in `M.stream(messages, system, tools, profile, callbacks)` is kept for test-mode override (existing `M._curl_cmd` pattern). Pass `nil` to use the registry default.

- [ ] **Step 1: Replace hardcoded TOOLS in `lua/thorny/provider/claude.lua`**

Remove the entire `local TOOLS = { ... }` block (web_search through MultiEdit, including the `M.TOOLS = TOOLS` line).

Add at the top of the file, after `M._curl_cmd = 'curl'`:

```lua
local registry = require('thorny.tools.registry')
```

In `M.stream`, change the body line:
```lua
    tools      = tools or TOOLS,
```
to:
```lua
    tools      = tools or registry.get_definitions(),
```

- [ ] **Step 2: Commit**

```bash
git add lua/thorny/provider/claude.lua
git commit -m "refactor: claude.lua reads tool definitions from registry"
```

---

## Task 4: Wire `chat.lua` dispatch to registry

**Files:**
- Modify: `lua/thorny/ui/chat.lua`

**Interfaces:**
- Consumes:
  - `require('thorny.tools.registry').get(name)` → `spec | nil`
  - `spec.mode` — `'auto' | 'pending' | 'server'`
  - `spec.execute(input, ctx)` → `string` (auto tools only)
- Changes:
  1. `send_message`: add `on_tools_done` callback; update `on_pause` and stream re-send calls to pass `nil` for tools (no more `provider_mod.TOOLS`)
  2. `on_tool_use`: skip display for `'auto'` mode tools (ReadFile shown inline via `on_tools_done`, not as a pending edit block)
  3. `apply_pending_edit`: replace the if/elseif tool-name chain with a `registry.get` lookup — keeps the buffer-based edit logic intact, just delegates routing to the registry

- [ ] **Step 1: Add registry require and `on_tools_done` to `send_message`**

At the top of `lua/thorny/ui/chat.lua`, add:
```lua
local tool_registry = require('thorny.tools.registry')
```

Inside `send_message`, replace the `callbacks` table with the version below. Key changes vs current:
- `on_tool_use` skips display for `auto`-mode tools (ReadFile is shown via `on_tools_done` instead)
- `on_tools_done` is added — dispatches auto tools immediately and re-sends; parks at pending UI for edit tools
- `on_pause` and the two `provider_mod.stream` re-send calls pass `nil` instead of `provider_mod.TOOLS`

```lua
  local response_text = ''

  local callbacks
  callbacks = {
    on_token = function(text)
      response_text = response_text .. text
      M.append_text(a, text)
    end,

    on_tool_use = function(tool_call)
      local spec = tool_registry.get(tool_call.name)
      if spec and spec.mode == 'pending' then
        agent_mod.add_pending_edit(a, tool_call)
        M.append_tool_use(a, tool_call)
      end
      -- auto-mode tools (ReadFile) are handled silently in on_tools_done
    end,

    -- stop_reason == 'tool_use': all client tool calls for this turn are done.
    -- Add the full assistant turn to history (fixes tool_result round-trips),
    -- execute auto tools and re-send, or park at the pending-edit UI.
    on_tools_done = function(content_blocks)
      table.insert(a.history, { role = 'assistant', content = content_blocks })
      response_text = ''  -- reset; next turn accumulates fresh text

      local has_auto = false
      for _, blk in ipairs(content_blocks) do
        if blk.type == 'tool_use' then
          local spec = tool_registry.get(blk.name)
          if spec and spec.mode == 'auto' then
            has_auto = true
            local ctx    = { cwd = vim.fn.getcwd() }
            local result = spec.execute(blk.input, ctx)
            agent_mod.add_tool_result(a, blk.id, result)
            local label = blk.input.file_path or blk.input.path or blk.name
            append_history(a.buf, { '[' .. blk.name .. ': ' .. label .. ']' })
          elseif has_auto then
            -- Mixed turn: auto + pending. Add placeholder so the API accepts
            -- the re-send; the pending edit was already shown via on_tool_use.
            agent_mod.add_tool_result(a, blk.id, 'Deferred: awaiting file reads in this turn.')
          end
        end
      end

      if has_auto then
        provider_mod.stream(a.history, system, nil, profile, callbacks)
      else
        -- Pure pending-edit turn — wait for user to press <leader>ha
        append_history(a.buf, { '' })
        require('thorny.persist').save_agent(a)
      end
    end,

    on_pause = function(content_blocks)
      table.insert(a.history, { role = 'assistant', content = content_blocks })
      provider_mod.stream(a.history, system, nil, profile, callbacks)
    end,

    on_done = function()
      agent_mod.add_message(a, 'assistant', response_text)
      append_history(a.buf, { '' })
      require('thorny.persist').save_agent(a)
    end,

    on_error = function(msg)
      append_history(a.buf, { '[error: ' .. msg .. ']', '' })
    end,
  }
  provider_mod.stream(a.history, system, nil, profile, callbacks)
```

- [ ] **Step 2: Replace `apply_pending_edit` dispatch with registry lookup**

Replace the body of `M.apply_pending_edit` (the `apply_edit` inner function and the if/elseif chain) while keeping the buffer-based edit mechanics intact:

```lua
function M.apply_pending_edit(a)
  local tool_call = agent_mod.pop_pending_edit(a)
  if not tool_call then
    vim.notify('thorny: no pending edits', vim.log.levels.INFO)
    return
  end

  local spec = tool_registry.get(tool_call.name)
  if not spec or spec.mode ~= 'pending' then
    vim.notify('thorny: unknown pending tool: ' .. tool_call.name, vim.log.levels.WARN)
    return
  end

  local input = tool_call.input
  local cwd   = vim.fn.getcwd()

  local function apply_edit(file_path, old_string, new_string)
    local abs = file_path:sub(1, 1) == '/' and file_path or (cwd .. '/' .. file_path)
    local bufnr = vim.fn.bufnr(abs)
    if bufnr == -1 then
      bufnr = vim.fn.bufadd(abs)
      vim.fn.bufload(bufnr)
    end
    local lines   = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local content = table.concat(lines, '\n')
    local escaped = old_string:gsub('[%(%)%.%%%+%-%*%?%[%^%$]', '%%%1')
    local new_content, n = content:gsub(escaped, new_string, 1)
    if n == 0 then
      vim.notify('thorny: Edit failed — old_string not found in ' .. file_path, vim.log.levels.ERROR)
      return false
    end
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(new_content, '\n', { plain = true }))
    return true
  end

  local ok = false
  if tool_call.name == 'Edit' then
    ok = apply_edit(input.file_path, input.old_string, input.new_string)
  elseif tool_call.name == 'Write' then
    local abs = input.file_path:sub(1, 1) == '/' and input.file_path or (cwd .. '/' .. input.file_path)
    local bufnr = vim.fn.bufadd(abs)
    vim.fn.bufload(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(input.content or '', '\n', { plain = true }))
    ok = true
  elseif tool_call.name == 'MultiEdit' then
    ok = true
    for _, edit in ipairs(input.edits or {}) do
      if not apply_edit(input.file_path, edit.old_string, edit.new_string) then
        ok = false
        break
      end
    end
  else
    -- Third-party pending tool — spec is responsible for its own apply logic
    vim.notify('thorny: pending tool "' .. tool_call.name .. '" has no built-in apply handler', vim.log.levels.WARN)
    return
  end

  if ok then
    agent_mod.add_tool_result(a, tool_call.id, tool_call.name .. ' applied successfully.')
    append_history(a.buf, { '', '✓ edit applied to ' .. (input.file_path or tool_call.name), '' })
  end
end
```

- [ ] **Step 3: Commit**

```bash
git add lua/thorny/ui/chat.lua
git commit -m "refactor: chat.lua dispatches tools via registry; add on_tools_done"
```

---

## Task 5: Register built-ins in `init.lua` and expose public API

**Files:**
- Modify: `lua/thorny/init.lua`

**Interfaces:**
- Produces: `M.register_tool(spec)` — public API for third-party plugins
- Built-in registration order must be: `web_search`, `ReadFile`, `Edit`, `Write`, `MultiEdit`
  (registry applies `cache_control` to the last non-server tool, which will be `MultiEdit`)

- [ ] **Step 1: Add built-in registration and public `register_tool` to `init.lua`**

At the bottom of `M.setup()`, just before the global keymaps block, add:

```lua
  -- Register built-in tools. Order matters: cache_control is applied to the
  -- last non-server tool (MultiEdit) by registry.get_definitions().
  local tool_registry = require('thorny.tools.registry')
  tool_registry.register(require('thorny.tools.builtin.web_search'))
  tool_registry.register(require('thorny.tools.builtin.read_file'))
  tool_registry.register(require('thorny.tools.builtin.edit'))
  tool_registry.register(require('thorny.tools.builtin.write'))
  tool_registry.register(require('thorny.tools.builtin.multi_edit'))
```

After the closing `end` of `M.setup`, add the public extension API:

```lua
-- Public API for third-party plugins.
-- Call from your plugin's setup() after require('thorny').setup() has run.
--
-- Example auto tool:
--   require('thorny').register_tool({
--     definition = {
--       name = 'RunTests',
--       description = 'Run the test suite and return output.',
--       input_schema = {
--         type = 'object',
--         properties = { pattern = { type = 'string' } },
--         required = {},
--       },
--     },
--     mode = 'auto',
--     execute = function(input, ctx)
--       return vim.fn.system('npm test -- ' .. (input.pattern or ''))
--     end,
--   })
function M.register_tool(spec)
  require('thorny.tools.registry').register(spec)
end
```

- [ ] **Step 2: Commit**

```bash
git add lua/thorny/init.lua
git commit -m "feat: register built-in tools in setup(); expose register_tool public API"
```

---

## Task 6: Smoke-test and merge

- [ ] **Step 1: Open Neovim and run `:ThornyNew test-registry`**

Verify no errors in `:messages`. The agent buffer should open normally.

- [ ] **Step 2: Send a message that triggers ReadFile**

Type a message like `"What does context.lua do?"` and press `<CR>`.

Expected: Claude calls `ReadFile` for `lua/thorny/context.lua`, the buffer shows `[ReadFile: lua/thorny/context.lua]`, and Claude responds with an answer.

- [ ] **Step 3: Send a message that triggers an edit**

Type `"Add a comment at the top of lua/thorny/tools/registry.lua"` and press `<CR>`.

Expected: Claude calls `ReadFile` then `Edit`; a pending-edit block appears; `<leader>ha` applies it.

- [ ] **Step 4: Merge to main**

```bash
git checkout main
git merge --no-ff feat/tool-registry -m "feat: pluggable tool registry

Extracts hardcoded TOOLS and dispatch logic into a central registry.
Built-ins (web_search, ReadFile, Edit, Write, MultiEdit) self-register
in setup(). Third-party plugins extend via require('thorny').register_tool().
Fixes latent bug where tool_use turns stored only plain text in history."
```
