-- Tests for zkmake
-- Run: nvim --headless -u NONE -c "set rtp+=." -c "luafile tests/zkmake_spec.lua" -c "qa"

local pass, fail = 0, 0
local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    pass = pass + 1
    print("  PASS  " .. name)
  else
    fail = fail + 1
    print("  FAIL  " .. name .. "\n        " .. tostring(err))
  end
end

local function eq(got, want)
  if got ~= want then
    error(string.format("got %s, want %s", vim.inspect(got), vim.inspect(want)), 2)
  end
end

local M = require("zkmake")

-- Helper: set buffer line and cursor (1-indexed col)
local function cursor_at(line, col)
  vim.cmd("enew!")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { line })
  vim.api.nvim_win_set_cursor(0, { 1, col - 1 })
end

-- === parse_wikilink ===

print("\n--- parse_wikilink ---")

test("plain title", function()
  local t, h = M._parse_wikilink("new note")
  eq(t, "new note"); eq(h, nil)
end)

test("title with heading", function()
  local t, h = M._parse_wikilink("note#heading")
  eq(t, "note"); eq(h, "heading")
end)

test("trailing # ignored", function()
  local t, h = M._parse_wikilink("note#")
  eq(t, "note"); eq(h, nil)
end)

test("multiple # splits on first", function()
  local t, h = M._parse_wikilink("a#b#c")
  eq(t, "a"); eq(h, "b#c")
end)

-- === get_wikilink ===

print("\n--- get_wikilink ---")

test("cursor inside wikilink", function()
  cursor_at("see [[new note]] here", 10)
  eq(M._get_wikilink(), "new note")
end)

test("cursor on opening bracket", function()
  cursor_at("see [[hello]] x", 6)
  eq(M._get_wikilink(), "hello")
end)

test("cursor just before closing bracket", function()
  cursor_at("see [[hello]] x", 12)
  eq(M._get_wikilink(), "hello")
end)

test("cursor outside — before link", function()
  cursor_at("before [[link]] text", 3)
  eq(M._get_wikilink(), nil)
end)

test("cursor outside — after link", function()
  cursor_at("x [[link]] after", 14)
  eq(M._get_wikilink(), nil)
end)

test("empty wikilink returns nil", function()
  cursor_at("x [[ ]] y", 5)
  eq(M._get_wikilink(), nil)
end)

test("with heading fragment", function()
  cursor_at("x [[note#heading]] y", 10)
  eq(M._get_wikilink(), "note#heading")
end)

test("multiple links — cursor in first", function()
  cursor_at("[[first]] and [[second]]", 4)
  eq(M._get_wikilink(), "first")
end)

test("multiple links — cursor in second", function()
  cursor_at("[[first]] and [[second]]", 20)
  eq(M._get_wikilink(), "second")
end)

test("multiple links — cursor between", function()
  cursor_at("[[first]] and [[second]]", 12)
  eq(M._get_wikilink(), nil)
end)

test("trims whitespace", function()
  cursor_at("[[  spaced  ]]", 7)
  eq(M._get_wikilink(), "spaced")
end)

test("link at start of line", function()
  cursor_at("[[start]] more", 4)
  eq(M._get_wikilink(), "start")
end)

test("link at end of line", function()
  cursor_at("more [[end]]", 10)
  eq(M._get_wikilink(), "end")
end)

-- === resolve_buf_path ===

print("\n--- resolve_buf_path ---")

test("normal path", function()
  vim.cmd("enew!")
  vim.api.nvim_buf_set_name(0, "/tmp/notes/note.md")
  local p = M._resolve_buf_path()
  assert(p and p:match("note%.md$"), "expected path ending in note.md, got: " .. tostring(p))
end)

test("strips oil:// prefix", function()
  vim.cmd("enew!")
  vim.api.nvim_buf_set_name(0, "oil:///Users/foo/notes/")
  eq(M._resolve_buf_path(), "/Users/foo/notes/")
end)

test("strips fugitive:// prefix", function()
  vim.cmd("enew!")
  vim.api.nvim_buf_set_name(0, "fugitive:///Users/foo/.git//abc/f.md")
  eq(M._resolve_buf_path(), "/Users/foo/.git//abc/f.md")
end)

test("strips generic scheme://", function()
  vim.cmd("enew!")
  -- Neovim only preserves scheme:// buffer names it recognizes as URIs.
  -- Use a simple alpha-only scheme to test the generic pattern.
  vim.api.nvim_buf_set_name(0, "zipfile:///tmp/file.md")
  eq(M._resolve_buf_path(), "/tmp/file.md")
end)

test("rejects remote scp://", function()
  vim.cmd("enew!")
  vim.api.nvim_buf_set_name(0, "scp://host/path/file.md")
  eq(M._resolve_buf_path(), nil)
end)

test("rejects oil-ssh://", function()
  vim.cmd("enew!")
  vim.api.nvim_buf_set_name(0, "oil-ssh://host/notes/")
  eq(M._resolve_buf_path(), nil)
end)

test("empty buffer returns nil", function()
  vim.cmd("enew!")
  eq(M._resolve_buf_path(), nil)
end)

-- === summary ===

print(string.format("\n%d passed, %d failed\n", pass, fail))
if fail > 0 then vim.cmd("cq!") end
vim.cmd("qa!")
