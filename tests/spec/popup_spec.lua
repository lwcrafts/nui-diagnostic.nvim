local config = require("nui-diagnostic.config")
local popup = require("nui-diagnostic.popup")

describe("nui-diagnostic.popup", function()
  local original_create_buf
  local original_open_win
  local original_buf_set_lines
  local original_win_is_valid
  local original_win_close
  local original_set_option_value

  local bufs = {}
  local wins = {}
  local open_win_calls = {}
  local extmarks = {}

  before_each(function()
    original_create_buf = vim.api.nvim_create_buf
    original_open_win = vim.api.nvim_open_win
    original_buf_set_lines = vim.api.nvim_buf_set_lines
    original_win_is_valid = vim.api.nvim_win_is_valid
    original_win_close = vim.api.nvim_win_close
    original_set_option_value = vim.api.nvim_set_option_value

    bufs = {}
    wins = {}
    open_win_calls = {}

    local next_bufnr = 100
    local next_winid = 200

    vim.api.nvim_create_buf = function(listed, scratch)
      local bufnr = next_bufnr
      next_bufnr = next_bufnr + 1
      bufs[bufnr] = { listed = listed, scratch = scratch, lines = {} }
      return bufnr
    end

    vim.api.nvim_open_win = function(bufnr, enter, opts)
      local winid = next_winid
      next_winid = next_winid + 1
      wins[winid] = { bufnr = bufnr, enter = enter, opts = opts, winid = winid }
      table.insert(open_win_calls, { bufnr = bufnr, enter = enter, opts = opts, winid = winid })
      return winid
    end

    vim.api.nvim_buf_set_lines = function(bufnr, start_idx, end_idx, strict, lines)
      if start_idx == 0 and end_idx == -1 then
        bufs[bufnr].lines = vim.deepcopy(lines)
      end
    end

    vim.api.nvim_win_is_valid = function(winid)
      return wins[winid] ~= nil
    end

    vim.api.nvim_win_close = function(winid, force)
      wins[winid] = nil
    end

    vim.api.nvim_set_option_value = function(name, value, opts)
      -- mock
    end

    vim.api.nvim_create_namespace = function(name)
      return 1
    end

    extmarks = {}
    vim.api.nvim_buf_set_extmark = function(bufnr, ns_id, line, col, opts)
      extmarks[bufnr] = extmarks[bufnr] or {}
      table.insert(extmarks[bufnr], { ns_id = ns_id, row = line, col = col, opts = opts })
      return 1
    end

    config.setup()
  end)

  after_each(function()
    vim.api.nvim_create_buf = original_create_buf
    vim.api.nvim_open_win = original_open_win
    vim.api.nvim_buf_set_lines = original_buf_set_lines
    vim.api.nvim_win_is_valid = original_win_is_valid
    vim.api.nvim_win_close = original_win_close
    vim.api.nvim_set_option_value = original_set_option_value
    vim.api.nvim_buf_set_extmark = nil
    vim.api.nvim_create_namespace = nil
    popup.close()
  end)

  it("opens a floating window with title via nvim_open_win", function()
    local diagnostics = {
      { message = "Error: something went wrong", severity = vim.diagnostic.severity.ERROR }
    }
    popup.open({
      diagnostics = diagnostics,
      actions = {
        { action = { title = "Fix it" } }
      },
      on_action = function() end,
      bufnr = 1,
    })

    assert.are.same(2, #open_win_calls)
    local win_opts = open_win_calls[1].opts
    assert.are.same("rounded", win_opts.border)
    assert.are.same({ { "Diagnostic ", "FloatTitle" } }, win_opts.title)
    assert.are.same("left", win_opts.title_pos)

    local action_opts = open_win_calls[2].opts
    assert.are.same("rounded", action_opts.border)
    assert.are.same({ { "Code actions", "FloatTitle" } }, action_opts.title)
    assert.are.same("left", action_opts.title_pos)
  end)

  it("adds highlight extmarks for diagnostics", function()
    local diagnostics = {
      { message = "Error message", severity = vim.diagnostic.severity.ERROR },
      { message = "Warn message", severity = vim.diagnostic.severity.WARN }
    }
    popup.open({
      diagnostics = diagnostics,
      actions = {},
      on_action = function() end,
      bufnr = 1,
    })

    assert.are.same(1, #open_win_calls)
    local diag_bufnr = open_win_calls[1].bufnr
    
    assert.is_truthy(extmarks[diag_bufnr])
    assert.are.same(2, #extmarks[diag_bufnr])
    
    -- Error highlight
    assert.are.same(0, extmarks[diag_bufnr][1].row)
    assert.are.same("DiagnosticError", extmarks[diag_bufnr][1].opts.hl_group)
    
    -- Warn highlight
    assert.are.same(1, extmarks[diag_bufnr][2].row)
    assert.are.same("DiagnosticWarn", extmarks[diag_bufnr][2].opts.hl_group)
  end)
end)

