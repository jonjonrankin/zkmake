if vim.g.loaded_zkmake then return end
vim.g.loaded_zkmake = true

vim.api.nvim_create_user_command("ZkMake", function()
  require("zkmake").setup()
  require("zkmake").make()
end, { desc = "Create or navigate to note under [[wikilink]]" })
