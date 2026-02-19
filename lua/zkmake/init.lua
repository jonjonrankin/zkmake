local M = {}

M.config = {
  mapping = "<leader>zm",
  on_existing = "edit", -- "edit" | "warn" | "nothing"
}

--- Strip any scheme:// prefix from a buffer name. Returns path or nil.
function M._resolve_buf_path(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr or 0)
  if name == "" then return nil end
  local path = name:match("^%a[%w%.%+%-]*://(.*)$")
  if path then
    return path:match("^/") and path or nil
  end
  return vim.fn.expand("%:p")
end

--- Get the wikilink text under the cursor, or nil.
function M._get_wikilink()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1

  -- Find nearest [[ before/at cursor
  local open = nil
  for i = col, 2, -1 do
    if line:sub(i - 1, i) == "[[" then
      open = i + 1
      break
    end
  end
  if not open then return nil end

  -- Make sure no ]] between [[ and cursor
  if line:sub(open, col):find("]]", 1, true) then return nil end

  -- Find nearest ]] after cursor
  local close = nil
  for j = col, #line - 1 do
    if line:sub(j, j + 1) == "]]" then
      close = j - 1
      break
    end
  end
  if not close then return nil end

  local text = vim.trim(line:sub(open, close))
  return text ~= "" and text or nil
end

--- Parse "title#heading" into title, heading (or nil).
function M._parse_wikilink(text)
  local title, heading = text:match("^(.-)#(.+)$")
  if title and title ~= "" then
    return title, heading
  end
  return text:match("^(.-)#?$"), nil
end

function M.make()
  local zk_util = require("zk.util")

  local buf_path = M._resolve_buf_path()
  if not buf_path then
    vim.notify("ZkMake: cannot resolve buffer path", vim.log.levels.WARN)
    return
  end

  local notebook_root = zk_util.notebook_root(buf_path)
  if not notebook_root then
    vim.notify("ZkMake: not inside a zk notebook", vim.log.levels.WARN)
    return
  end

  local raw = M._get_wikilink()
  if not raw then
    vim.notify("ZkMake: cursor is not inside a [[wikilink]]", vim.log.levels.WARN)
    return
  end

  local title, heading = M._parse_wikilink(raw)

  -- Build the filepath: <notebook_root>/<title>.md
  -- The filename matches the wikilink text so [[title]] resolves to title.md
  local note_path = notebook_root .. "/" .. title .. ".md"

  -- Check if the file already exists
  if vim.fn.filereadable(note_path) == 1 then
    if M.config.on_existing == "edit" then
      vim.cmd("edit " .. vim.fn.fnameescape(note_path))
      if heading then
        vim.fn.search("^#\\+\\s\\+" .. vim.fn.escape(heading, "\\"), "w")
      end
    elseif M.config.on_existing == "warn" then
      vim.notify("ZkMake: note already exists: " .. note_path, vim.log.levels.INFO)
    end
    return
  end

  -- Create the file with an H1 title
  local fd = io.open(note_path, "w")
  if not fd then
    vim.notify("ZkMake: could not create " .. note_path, vim.log.levels.ERROR)
    return
  end
  fd:write("# " .. title .. "\n")
  fd:close()

  vim.cmd("edit " .. vim.fn.fnameescape(note_path))
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  local ok, commands = pcall(require, "zk.commands")
  if ok then
    commands.add("ZkMake", function() M.make() end)
  end

  vim.api.nvim_create_user_command("ZkMake", M.make, {
    desc = "Create or navigate to note under [[wikilink]]",
  })

  if M.config.mapping then
    vim.keymap.set("n", M.config.mapping, M.make, {
      desc = "ZkMake",
      silent = true,
    })
  end
end

return M
