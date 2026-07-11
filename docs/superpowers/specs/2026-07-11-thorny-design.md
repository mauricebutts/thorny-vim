# thorny.nvim — Design Spec

**Date:** 2026-07-11
**Status:** Approved

---

## Overview

`thorny.nvim` is a Lua Neovim plugin that provides an agnostic AI agent harness. It lets you spin up, configure, and navigate multiple AI agents as naturally as you navigate buffers — with Telescope to pick, buffer-style navigation once open, and streaming responses rendered in real time.

The initial provider is Anthropic Claude. The provider layer is abstracted so additional providers can be added later.

---

## Architecture

```
thorny.nvim/
├── lua/thorny/
│   ├── init.lua          -- entry point, setup(), public API
│   ├── agent.lua         -- Agent model: state, history, persona
│   ├── registry.lua      -- manages the pool of active agents + profiles
│   ├── provider/
│   │   ├── init.lua      -- provider interface (abstract)
│   │   └── claude.lua    -- Anthropic SSE streaming via vim.loop.spawn
│   ├── context.lua       -- project file tree + buffer context gathering
│   ├── ui/
│   │   ├── chat.lua      -- chat buffer rendering, keymaps, patch application
│   │   └── picker.lua    -- Telescope integration for agent switching
│   └── persist.lua       -- serialize/deserialize agent history to disk
└── plugin/thorny.vim     -- vim-plug entry point, auto-loads thorny
```

---

## Agent Model

Each agent is a Lua table:

```lua
{
  name         = "refactor",       -- human-readable identifier
  persona      = "You are...",     -- system prompt / persona
  history      = {},               -- ordered list of {role, content} messages
  profile      = "personal",       -- which credentials profile to use
  context_mode = "project",        -- "none" | "buffer" | "project"
  buf          = 42,               -- Neovim buffer number for this agent
}
```

Agents are managed by the **registry** — an in-memory Lua table. On startup, thorny loads persisted agents from `~/.local/share/nvim/thorny/<name>.json`. On `:ThornyPersist` or agent close, they serialize back to disk.

---

## Profiles (Credentials)

Profiles are named API key configurations stored in `~/.config/nvim/thorny/profiles.json`:

```json
{
  "personal": {
    "api_key": "sk-ant-..."
  },
  "work-org-a": {
    "api_key": "sk-ant-..."
  },
  "work-org-b": {
    "api_key": "sk-ant-..."
  }
}
```

- Each agent has an optional `profile` field. If unset, falls back to a `default` profile.
- Profiles can be switched per-agent at any time.
- `profiles.json` should be added to `.gitignore`. Thorny will warn if the file has world-readable permissions (`chmod 600` recommended).

---

## Provider Interface

`provider/init.lua` defines the interface all providers must implement:

```lua
{
  stream(messages, system, tools, profile, on_token, on_tool_use, on_done)
  -- on_token(text)             called for each streamed text token
  -- on_tool_use(tool_call)     called when a tool_use block is complete
  -- on_done()                  called when the stream ends
}
```

`provider/claude.lua` implements this using `vim.loop.spawn` to run `curl` with `-N --no-buffer` against the Anthropic Messages API (SSE). Tokens are parsed line-by-line from stdout as they arrive and dispatched via the callbacks.

---

## Context Gathering

`context.lua` builds a context snapshot before each message send. Behavior depends on the agent's `context_mode`:

- **`"none"`** — no project context injected
- **`"buffer"`** — current buffer contents + cursor position
- **`"project"`** — file tree (respecting `.gitignore`) + pinned files + current buffer

The snapshot is prepended to the system prompt. For large projects, file contents are truncated by estimated token count to stay within Claude's context window. Pinned files (attached via `<leader>ac`) are always included in full before truncation of the rest.

---

## Tools (Edit API)

Thorny defines the following tools in every Claude request, matching the Claude Code model:

| Tool | Description |
|---|---|
| `Edit` | Replace `old_string` with `new_string` in a file |
| `Write` | Write full contents to a file |
| `MultiEdit` | Multiple `Edit` operations on a single file |

When Claude returns a `tool_use` block, Thorny:
1. Renders a highlighted **pending edit block** inline in the chat buffer
2. Waits for the user to press `<leader>ha` to apply
3. On apply, writes the change to the target file buffer (or disk if not open)

Pending edits are stored per-agent until applied or the agent is killed.

---

## UI: Chat Buffer

Each agent has a dedicated Neovim buffer (`filetype=thorny`, `buftype=nofile`). The buffer is read-only above a separator line; the input area below is editable.

```
[thorny] refactor                    ← buffer name
──────────────────────────────────────
You: can you clean up the auth logic?
Claude: Sure! Here's what I'd change...

┌─ pending edit: auth/login.go ──────┐
│  - doOldThing()                    │
│  + doNewThing()                    │
└────────────────────────────────────┘

> _                                  ← input area
```

Streaming tokens are appended to the buffer in real time via `vim.schedule` to stay on the main thread.

---

## Keybindings

All bindings are buffer-local inside a thorny chat buffer unless noted.

| Key | Action |
|---|---|
| `<CR>` | Send message |
| `<leader>ha` | Apply pending edit to file |
| `<leader>ac` | Attach context — Telescope picker to pin project files |
| `<leader>an` | New agent |
| `<leader>as` | Switch agent — Telescope picker |
| `<leader>ak` | Kill current agent |

---

## Data Flow

```
You type a message + hit <CR>
        │
        ▼
context.lua builds snapshot (file tree + pinned files + current buffer)
        │
        ▼
claude.lua sends request via vim.loop.spawn (curl SSE)
  - messages: agent history + your new message
  - system:   persona + context snapshot
  - tools:    [Edit, Write, MultiEdit] definitions
        │
        ▼
Tokens stream into chat buffer in real time
        │
        ├─ text content  → appended to chat buffer token by token
        │
        └─ tool_use block → rendered as highlighted pending edit block
                │
                └─ <leader>ha → thorny writes edit to file buffer
                                agent history updated with tool result
```

---

## Persistence

Agent conversation history is serialized as JSON to `~/.local/share/nvim/thorny/<agent-name>.json`. This includes:

- `name`, `persona`, `profile`, `context_mode`
- Full `history` array

Triggered by `:ThornyPersist` (all agents) or automatically on agent kill / Neovim exit.

---

## Commands

| Command | Description |
|---|---|
| `:ThornyNew [name]` | Create and open a new agent |
| `:ThornySwitch` | Open Telescope agent picker |
| `:ThornyKill` | Kill the current agent |
| `:ThornyPersist` | Serialize all agents to disk |
| `:ThornyProfile` | Open Telescope profile picker for current agent |

---

## Out of Scope (v1)

- Multiple AI providers beyond Claude
- Token counting / usage tracking UI
- Agent-to-agent communication
- MCP server integration
- Tree-sitter aware context selection
