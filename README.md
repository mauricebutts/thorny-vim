# thorny.nvim

A Neovim AI agent harness. Spin up multiple Claude agents as buffers, navigate between them like files, stream responses in real time, and apply code edits with a single keystroke.

## Requirements

- Neovim ≥ 0.9
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- `curl` (system)
- An [Anthropic API key](https://console.anthropic.com/)

## Installation

Add to your `init.vim` with vim-plug:

```vim
Plug 'your-username/thorny.nvim'
```

Then in your Lua config (or a `lua << EOF` block):

```lua
require('thorny').setup({
  default_profile      = 'personal',   -- name of the default profile
  default_context_mode = 'project',    -- 'none' | 'buffer' | 'project'
})
```

## Profiles (API Keys)

Create `~/.config/nvim/thorny/profiles.json`:

```json
{
  "personal":  { "api_key": "sk-ant-..." },
  "work-org-a": { "api_key": "sk-ant-..." },
  "work-org-b": { "api_key": "sk-ant-..." }
}
```

**Important:** run `chmod 600 ~/.config/nvim/thorny/profiles.json` and never commit this file.

## Keybindings

### Global

| Key | Action |
|---|---|
| `<leader>an` | New agent |
| `<leader>as` | Switch agent (Telescope picker) |
| `<leader>ak` | Kill current agent |

### Inside a thorny buffer

| Key | Action |
|---|---|
| `<CR>` | Send message |
| `<leader>ha` | Apply pending edit to file |
| `<leader>ac` | Attach context — Telescope picker to pin project files |

## Commands

| Command | Description |
|---|---|
| `:ThornyNew [name]` | Create and open a new agent |
| `:ThornySwitch` | Open Telescope agent picker |
| `:ThornyKill` | Kill the current agent buffer |
| `:ThornyPersist` | Save all agent histories to disk |
| `:ThornyProfile` | Switch the current agent's API profile |

## Context Modes

Each agent has a `context_mode` that controls what project context is sent with every message:

| Mode | Description |
|---|---|
| `none` | No project context — just your message and history |
| `buffer` | Current buffer contents only |
| `project` | Full file tree + pinned files + current buffer (like Claude Code) |

## How Edits Work

When you ask an agent to modify code, Claude responds with a structured edit proposal rendered inline in the chat buffer. Press `<leader>ha` to apply it directly to the target file. To decline, just type a follow-up message.

## Running Tests

```bash
nvim --headless --noplugin -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ {sequential=true}"
```
