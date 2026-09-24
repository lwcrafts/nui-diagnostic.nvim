local M = {}

function M.check()
  vim.health.start("nui-diagnostic.nvim")

  if vim.fn.has("nvim-0.10") == 1 then
    vim.health.ok("Neovim >= 0.10")
  else
    vim.health.warn("Neovim >= 0.10 is recommended")
  end



  local clients = vim.lsp.get_clients({ bufnr = vim.api.nvim_get_current_buf() })
  if #clients > 0 then
    vim.health.ok(string.format("%d LSP client(s) attached to current buffer", #clients))
  else
    vim.health.warn("No LSP clients attached to current buffer")
  end

  if vim.diagnostic.is_enabled() then
    vim.health.ok("Diagnostics are enabled")
  else
    vim.health.warn("Diagnostics are disabled")
  end
end

return M

