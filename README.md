# thorny.nvim

A Neovim AI agent harness. Spin up multiple Claude agents as buffers, navigate between them like files, stream responses in real time, and apply code edits with a single keystroke.

**Warning**: This is still WIP and may cause excessive token usage :)

## Requirements

- Neovim ≥ 0.9
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- `curl` (system)
- An [Anthropic API key](https://console.anthropic.com/)

## Installation

Add to your `init.vim` with vim-plug:

```vim
Plug 'your-username/thorny.nvim' # TODO fix this
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

## Extending with Custom Tools

Register custom tools from your Neovim config after `setup()`:

```lua
require('thorny').setup({ ... })

require('thorny').register_tool({
  definition = {
    name        = 'RunTests',
    description = 'Run the test suite and return its output.',
    input_schema = {
      type       = 'object',
      properties = {
        pattern = { type = 'string', description = 'Optional test filter pattern' },
      },
      required = {},
    },
  },
  mode = 'auto',
  execute = function(input, ctx)
    return vim.fn.system('npm test -- ' .. (input.pattern or ''))
  end,
})
```

### Tool modes

| Mode | Behaviour |
|---|---|
| `auto` | Executed immediately by thorny; result sent back to Claude; Claude continues |
| `pending` | Shown as a pending-edit block in the chat buffer; apply with `<leader>ha` |
| `server` | Executed by Anthropic's infrastructure (built-ins only, e.g. `web_search`) |

`auto` is the right choice for most custom tools. The `execute` function receives `input` (the arguments Claude passed) and `ctx` (a table with `cwd`), and must return a string.

## How Edits Work

When you ask an agent to modify code, Claude responds with a structured edit proposal rendered inline in the chat buffer. Press `<leader>ha` to apply it directly to the target file. To decline, just type a follow-up message.

## Running Tests

```bash
nvim --headless --noplugin -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ {sequential=true}"
```

## ToDo
* Project-scoped chat contexts — when opening thorny in a project, show only the agents created in that project (scoped by git root or cwd); easily browse and resume past chats per-project from a picker
  - ThornyOpenProject opens all of the used chats in that project in a list that the user can select from.
* Enable more providers OpenAI, as well as bespoke agents and local agents
* Compact conext and manage context 
* Context management (dont send the whole repo every time)
* Context - Send needed files
* Web search?
* Allow agent to manipulate vim buffers. ie: Open a new buffer with example code 
* Make tools wildely avalbile to all providers
* Make skills widely available to all providers
* Allow multi agent spin outs (where users could inspect those buffers if needed?)
* Maybe have hierarchy of profiles? ( Higher level models vs lower level models to save on cost? )

* Tools?

  - Web Search — search the internet
  - Web Fetch — retrieve page content
  - Code Execution — run code in a sandbox
  - Computer Use — vision-based screen interaction
  - Text Editor / Bash — file and shell operations
* Neovim built-in tools — expose native editor capabilities as agent tools
  - `GetDiagnostics` — surface current LSP errors/warnings; lets Claude verify edits didn't break anything
  - `FindReferences` — LSP-powered symbol usage search across the project (more precise than grep)
  - `GotoDefinition` — resolve a symbol to its definition file and line for code tracing
  - `Hover` — retrieve LSP type info and docs for a symbol at a position
  - `FindSymbol` — Tree-sitter query to locate a function/class/variable by name without reading a full file
  - `GetSymbols` — list all top-level symbols in a file (cheaper than ReadFile for understanding module shape)
  - `Grep` — ripgrep across the project for targeted pattern searches


