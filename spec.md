# zkmake — Neovim Plugin Spec

## Overview

A small `zk-nvim` companion plugin that replicates Obsidian's "create note from wikilink" behavior. When the cursor is inside a `[[wikilink]]` that references a note that doesn't exist yet, a single command creates the note via the `zk` LSP and opens it.

## Prior Art / Why This Doesn't Exist Yet

- **`zk-nvim`** provides `:ZkNew`, `:ZkNewFromTitleSelection`, and LSP go-to-definition — but none of these do "detect wikilink under cursor, check if it exists, create if missing" in one step.
- **`zk` LSP** has a code action to create a note from a *visual selection*, but no equivalent for an unresolved wikilink under the cursor.
- [Discussion #96](https://github.com/zk-org/zk-nvim/discussions/96) on `zk-nvim` (Jan 2023, zero replies) is someone trying to build exactly this with null-ls. They got stuck on wikilink extraction. No solution was ever posted.
- No standalone plugin exists for this.

This is a genuine gap — not a reinvention.

## Goals

1. Detect the wikilink under the cursor (text between `[[` and `]]`).
2. Determine whether a matching note already exists in the notebook.
3. If it doesn't exist, create it via `zk-nvim`'s LSP API (respecting the notebook's templates/config).
4. If it already exists, optionally navigate to it instead.
5. Expose a single command (`:ZkMake`) and a recommended mapping (`<leader>zm`).

## Non-Goals

- Replacing `zk-nvim` — this is a thin companion, not a fork.
- Handling non-markdown file types.
- Managing `zk` configuration or templates.

## Detailed Design

### 1. Wikilink Detection

- Parse the current line at the cursor position.
- Extract the text between the innermost `[[` and `]]` surrounding the cursor.
- If the cursor is not inside a wikilink, show a warning and abort.
- Support optional heading fragments (`[[note#heading]]`) — strip the fragment for file creation but preserve it for navigation.

### 2. Note Existence Check

Use `zk-nvim`'s Lua API to query the notebook index:

```lua
require("zk.api").list(path, {
  select = { "title", "absPath" },
  hrefs = { title },
}, function(err, notes)
  -- notes is empty → note doesn't exist
  -- notes has results → note exists, navigate to it
end)
```

If `hrefs` doesn't match by title cleanly, fall back to a `zk.api.list` call with `match` + `matchStrategy = "exact"`.

### 3. Note Creation

Use `zk-nvim`'s Lua API:

```lua
require("zk.api").new(path, {
  title = title,
  dir = dir,       -- optional: same dir as current buffer, or notebook root
  edit = true,     -- tells zk-nvim to open the new note
}, function(err, res)
  -- res.path contains the absolute path to the new note
  -- if edit = true didn't work, fall back to vim.cmd("edit " .. res.path)
end)
```

This respects the notebook's `zk` config (templates, filename format, etc.) without us having to know about any of it.

### 4. Navigation (existing note)

- If the note already exists, open it with `:edit <path>`.
- If a `#heading` fragment was present, search for the heading after opening.
- Alternatively, delegate to `vim.lsp.buf.definition()` which `zk`'s LSP already supports for resolved wikilinks.

### 5. Buffer Path Resolution

Plugins like `oil.nvim`, `fugitive`, and others set buffer names with URI
schemes (e.g. `oil:///Users/foo/notes/`, `fugitive:///...`). Both notebook
detection and the `zk` API calls require a real filesystem path, so we need
a generic normalisation step.

```lua
--- Resolve the current buffer's path, stripping any scheme:// prefix.
--- Returns the path string, or nil if the buffer is a remote/non-local URI.
local function resolve_buf_path()
  local bufname = vim.api.nvim_buf_get_name(0)

  -- Match any URI scheme per RFC 3986: starts with a letter, then
  -- letters/digits/+/./-  followed by ://
  local path = bufname:match("^%a[%w+.-]*://(.*)$")

  if path then
    -- Only accept absolute local paths (starts with /).
    -- Anything else (scp://host/..., oil-ssh://host/...) is remote.
    if path:match("^/") then
      return path
    end
    vim.notify("ZkMake: cannot operate on remote buffers", vim.log.levels.WARN)
    return nil
  end

  return vim.fn.expand("%:p")
end
```

**Why generic, not oil-specific?** Hard-coding `oil://` would break the
moment another plugin uses a different scheme. The RFC 3986 pattern covers
every known case (`oil://`, `fugitive://`, `scp://`, `oil-ssh://`, etc.)
without needing to know about specific plugins.

**Safety check:** After stripping the scheme we verify the remaining path
starts with `/`. If it doesn't, it's a remote URI (e.g. `scp://host/...`
strips to `host/...`) — we warn and abort rather than silently passing
garbage to `zk`.

| Plugin | Buffer name | After strip | Result |
|--------|------------|-------------|--------|
| oil.nvim | `oil:///Users/foo/notes/` | `/Users/foo/notes/` | Used |
| fugitive | `fugitive:///Users/foo/.git//abc/f.md` | `/Users/foo/.git//abc/f.md` | Used |
| scp/netrw | `scp://host/path/file.md` | `host/path/file.md` | Rejected (remote) |
| oil-ssh | `oil-ssh://host/path/` | `host/path/` | Rejected (remote) |
| normal file | `/Users/foo/notes/note.md` | no match | `expand("%:p")` used |

This `resolve_buf_path()` helper is called in exactly two places:

1. **Notebook detection** — passed to `require("zk.util").notebook_root()`.
2. **zk API calls** — passed as the `path` argument to `zk.api.new()` and `zk.api.list()`.

### 6. Notebook Detection

Use `zk-nvim`'s built-in utility with the resolved path:

```lua
local buf_path = resolve_buf_path()
if not buf_path then return end

local notebook_root = require("zk.util").notebook_root(buf_path)
if not notebook_root then
  vim.notify("Not inside a zk notebook", vim.log.levels.WARN)
  return
end
```

### 7. User Interface

| Interface | Value | Description |
|-----------|-------|-------------|
| Command | `:ZkMake` | Create or navigate to the note under cursor |
| Default mapping | `<leader>zm` | Calls `:ZkMake` |
| Filetype scope | `markdown` | Only active in markdown buffers |

The mapping should be opt-in (set via config) so it doesn't collide with user mappings.

### 8. Configuration

```lua
require("zkmake").setup({
  -- Set to false to skip creating the default <leader>zm mapping
  default_mapping = true,

  -- Custom mapping (only used if default_mapping is true)
  mapping = "<leader>zm",

  -- What to do when the note already exists: "edit" | "warn" | "nothing"
  on_existing = "edit",

  -- Extra options passed to zk.api.new() (e.g. dir, template, group)
  zk_new_opts = {},

  -- Automatically save the current buffer before creating the new note
  auto_save = false,
})
```

### 9. Plugin Structure

```
zkmake/
├── lua/
│   └── zkmake/
│       ├── init.lua          -- setup(), config merging, :ZkMake command
│       ├── wikilink.lua      -- cursor parsing / wikilink extraction
│       └── path.lua          -- resolve_buf_path(), URI scheme stripping
├── plugin/
│   └── zkmake.lua            -- auto-register command on load
├── spec.md
└── idea.md
```

Note: because `zk-nvim` handles all the heavy lifting (LSP communication, notebook detection, note creation), this plugin is intentionally small. The core logic is ~50-80 lines of Lua.

**Alternative:** This could also ship as a config snippet using `require("zk.commands").add("ZkMake", ...)` — no plugin structure needed at all. The plugin form is preferable if you want it to be installable via a package manager and shareable.

### 10. Registration as a zk-nvim Custom Command

Regardless of plugin structure, the command is registered using zk-nvim's custom command system:

```lua
require("zk.commands").add("ZkMake", function(options)
  -- 1. extract wikilink under cursor
  -- 2. check if note exists via zk.api.list
  -- 3. create via zk.api.new or navigate
end)
```

This gives us `:ZkMake` for free and follows `zk-nvim`'s patterns.

## Edge Cases

- Cursor not inside a wikilink -> show `vim.notify` warning.
- Current buffer is not inside a `zk` notebook -> error with helpful message (via `zk.util.notebook_root`).
- `zk-nvim` not installed -> error on `require("zk")` with a clear message.
- Wikilink contains characters invalid for filenames -> let `zk new` handle sanitisation, surface any errors.
- Nested brackets `[[foo [[bar]]]]` -> match the innermost pair around the cursor.
- Empty wikilink `[[]]` -> warn and abort.
- Buffer opened via a plugin that prepends a URI scheme (oil.nvim, fugitive, etc.) -> `resolve_buf_path()` strips the scheme and recovers the real filesystem path.
- Buffer is a remote URI (scp://, oil-ssh://, etc.) -> warn and abort; `zk` cannot operate on remote filesystems.

## Testing

- Unit tests for wikilink extraction (various cursor positions, edge cases, heading fragments).
- Unit tests for `resolve_buf_path()` (normal paths, `oil://`, `fugitive://`, `scp://`, empty buffer name, etc.).
- Integration tests using `zk.api` against a temp notebook directory.
- Use `plenary.nvim`'s test harness or `mini.test`.

## Dependencies

- Neovim >= 0.8
- [`zk-nvim`](https://github.com/zk-org/zk-nvim) (required)
- `zk` CLI installed and on `$PATH` (required by `zk-nvim`)
- A valid `zk` notebook (directory containing `.zk/`)
