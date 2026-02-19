local M = {}

M.config = {
  mapping = "<leader>zm",
  on_existing = "edit", -- "edit" | "warn" | "nothing"
  zk_new_opts = {},
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
  local zk_api = require("zk.api")
  local zk_util = require("zk.util")

  local buf_path = M._resolve_buf_path()
  if not buf_path then
    vim.notify("ZkMake: cannot resolve buffer path", vim.log.levels.WARN)
    return
  end

  if not zk_util.notebook_root(buf_path) then
    vim.notify("ZkMake: not inside a zk notebook", vim.log.levels.WARN)
    return
  end

  local raw = M._get_wikilink()
  if not raw then
    vim.notify("ZkMake: cursor is not inside a [[wikilink]]", vim.log.levels.WARN)
    return
  end

  local title, heading = M._parse_wikilink(raw)

  zk_api.list(buf_path, {
    select = { "title", "absPath" },
    hrefs = { title },
  }, function(err, notes)
    if err then
      vim.notify("ZkMake: " .. tostring(err), vim.log.levels.ERROR)
      return
    end

    if notes and #notes > 0 then
      if M.config.on_existing == "edit" then
        vim.schedule(function()
          vim.cmd("edit " .. vim.fn.fnameescape(notes[1].absPath))
          if heading then vim.fn.search("^#\\+\\s\\+" .. vim.fn.escape(heading, "\\"), "w") end
        end)
      elseif M.config.on_existing == "warn" then
        vim.notify("ZkMake: note already exists: " .. notes[1].absPath, vim.log.levels.INFO)
      end
      return
    end

    local opts = vim.tbl_extend("force", { title = title, edit = true }, M.config.zk_new_opts)
    zk_api.new(buf_path, opts, function(new_err, res)
      if new_err then
        vim.notify("ZkMake: " .. tostring(new_err), vim.log.levels.ERROR)
        return
      end
      if res and res.path then
        vim.schedule(function()
          if not vim.api.nvim_buf_get_name(0):find(res.path, 1, true) then
            vim.cmd("edit " .. vim.fn.fnameescape(res.path))
          end
        end)
      end
    end)
  end)
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
