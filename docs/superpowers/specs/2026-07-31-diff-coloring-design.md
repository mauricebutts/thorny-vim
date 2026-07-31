# Diff Coloring & Reject for Pending Edits

**Date:** 2026-07-31
**Status:** Approved

## Goal

Color pending-edit blocks in the thorny chat buffer (green for additions, red for removals) and add a reject keymap so users can discard a proposed edit without applying it.

## Background

When Claude proposes an Edit, Write, or MultiEdit, `append_tool_use` in `chat.lua` renders a box in the chat buffer using `│  + new line` and `│  - old line` prefixes. These are plain text today — no color, no reject path. The user accepts with `<leader>ha`.

## Design

### Coloring — `after/syntax/thorny.vim` (new file)

The buffer already sets `filetype=thorny`. A syntax file at `after/syntax/thorny.vim` matches the rendered line prefixes and links them to standard Neovim diff highlight groups:

```vim
syntax match ThornyDiffAdd    "^│  +.*"
syntax match ThornyDiffDelete "^│  -.*"
highlight default link ThornyDiffAdd    DiffAdd
highlight default link ThornyDiffDelete DiffDelete
```

- `DiffAdd` / `DiffDelete` are built-in groups present in every colorscheme.
- `highlight default link` means user colorscheme overrides are respected.
- Zero runtime cost — Neovim applies this once when the buffer opens.

### Reject — `<leader>hr` keymap

`M.reject_pending_edit(a)` in `chat.lua`:
1. Calls `agent_mod.pop_pending_edit(a)` — removes the edit from the queue.
2. If nothing pending, notifies and returns.
3. Calls `agent_mod.add_tool_result(a, tool_call.id, 'User rejected this edit.')` — records the rejection in history so Claude is aware if the user mentions it.
4. Appends `✗ edit rejected` to the chat buffer.

The keymap is registered alongside `<leader>ha` in `chat.open()`.

No auto-resend after reject — the user follows up naturally by typing.

## Files

| File | Change |
|---|---|
| `after/syntax/thorny.vim` | New — syntax rules for `+`/`-` lines |
| `lua/thorny/ui/chat.lua` | Add `M.reject_pending_edit`, register `<leader>hr` in `M.open` |

## What's Not Changing

- `apply_pending_edit` behavior is unchanged.
- No new dependencies.
- MultiEdit and Write blocks show a summary line (not individual diff lines) — coloring only affects Edit's `+`/`-` lines. This is acceptable for now.
