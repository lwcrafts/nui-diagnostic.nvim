local config = require("nui-diagnostic.config")
local diagnostic = require("nui-diagnostic.diagnostic")

local M = {}

local state = {
  autocmd_ids = {},
  keymaps = {},
  popups = {},
  bufnr = nil
}

local function popup_width(lines, opts)
  local width = opts.popup.width

  for _, line in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end

  local screen_max_width = math.max(20, vim.o.columns - 4)
  return math.min(width, opts.popup.max_width, screen_max_width)
end

local function popup_border_height(opts)
  if not opts.popup.border_style or opts.popup.border_style == "none" then
    return 0
  end

  return 2
end

local function popup_height(lines, opts)
  return math.min(#lines, opts.popup.max_height) + popup_border_height(opts)
end

local function popup_border_offset(opts)
  return popup_border_height(opts) > 0 and 1 or 0
end

local function popup_placement(diag_lines, code_action_lines, opts)
  local diag_height = #diag_lines > 0 and popup_height(diag_lines, opts) or 0
  local code_action_height = #code_action_lines > 0 and popup_height(code_action_lines, opts) or 0
  local total_height = diag_height + code_action_height
  local border_offset = popup_border_offset(opts)
  local row = opts.popup.position.row
  local lines_below = vim.api.nvim_win_get_height(0) - vim.fn.winline()
  local below_gap = math.max(row - 1, 0)
  local open_above = total_height > lines_below - below_gap

  if not open_above then
    return {
      anchor = "NW",
      diag_row = row + border_offset,
      code_action_row = row + diag_height + border_offset
    }
  end

  local bottom_row = -math.max(row, 1) - border_offset
  return {
    anchor = "SW",
    diag_row = bottom_row - code_action_height,
    code_action_row = bottom_row
  }
end

local function make_popup(lines, width, row, title, opts, anchor)
  local height = math.min(#lines, opts.popup.max_height)

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  local win_opts = {
    relative = "cursor",
    anchor = anchor,
    row = row,
    col = opts.popup.position.col,
    width = width,
    height = height,
    style = "minimal",
    border = opts.popup.border_style,
  }

  if title then
    win_opts.title = { { title, "FloatTitle" } }
    win_opts.title_pos = "left"
  end

  local winid = vim.api.nvim_open_win(bufnr, false, win_opts)

  for k, v in pairs(opts.popup.win_options or {}) do
    vim.api.nvim_set_option_value(k, v, { win = winid })
  end

  return {
    bufnr = bufnr,
    winid = winid,
    unmount = function(self)
      if vim.api.nvim_win_is_valid(self.winid) then
        vim.api.nvim_win_close(self.winid, true)
      end
      if vim.api.nvim_buf_is_valid(self.bufnr) then
        vim.api.nvim_buf_delete(self.bufnr, { force = true })
      end
    end
  }
end

---@param actions NuiDiagnosticActionTuple[]
---@param keys string[]
local function action_lines(actions, keys)
  local lines = {}

  for idx, action_tuple in ipairs(actions) do
    local key = keys[idx]
    if not key then
      break
    end

    table.insert(lines, string.format(" [%s] %s", key, action_tuple.action.title or "Untitled action"))
  end

  return lines
end

local function clear_autocmds()
  for _, autocmd_id in ipairs(state.autocmd_ids) do
    pcall(vim.api.nvim_del_autocmd, autocmd_id)
  end
  state.autocmd_ids = {}
end

local function clear_keymaps()
  if not state.bufnr or not vim.api.nvim_buf_is_valid(state.bufnr) then
    state.keymaps = {}
    return
  end

  for _, key in ipairs(state.keymaps) do
    pcall(vim.keymap.del, "n", key, { buffer = state.bufnr })
  end

  state.keymaps = {}
end

function M.close()
  clear_autocmds()
  clear_keymaps()

  for _, popup in ipairs(state.popups) do
    pcall(function ()
      popup:unmount()
    end)
  end

  state.popups = {}
  state.bufnr = nil
end

function M.is_open()
  for _, popup in ipairs(state.popups) do
    if popup.winid and vim.api.nvim_win_is_valid(popup.winid) then
      return true
    end
  end

  return false
end

--- @param opts {
  --- diagnostics: vim.Diagnostic[],
  --- actions: NuiDiagnosticActionTuple[],
  --- on_action: fun(action:NuiDiagnosticActionTuple),
  --- bufnr?: integer,
  --- }
function M.open(opts)
  M.close()

  local plugin_opts = config.get()
  local diagnostics = opts.diagnostics or {}
  local actions = opts.actions or {}
  local diag_lines = {}
  state.bufnr = opts.bufnr or vim.api.nvim_get_current_buf()

  if plugin_opts.diagnostics.enabled then
    diag_lines = diagnostic.lines(diagnostics, plugin_opts.diagnostics)
  end

  local code_action_lines = {}
  if plugin_opts.code_actions.enabled then
    code_action_lines = action_lines(actions, plugin_opts.code_actions.keys or {})
  end

  if #diag_lines == 0 and #code_action_lines == 0 then return end

  local all_lines = vim.list_extend(vim.deepcopy(diag_lines), code_action_lines)
  local width = popup_width(all_lines, plugin_opts)
  local placement = popup_placement(diag_lines, code_action_lines, plugin_opts)

  if #diag_lines > 0 then
    local popup = make_popup(diag_lines, width, placement.diag_row, "Diagnostic ", plugin_opts, placement.anchor)
    table.insert(state.popups, popup)

    local ns_id = vim.api.nvim_create_namespace("nui-diagnostic")
    local hl_map = {
      [vim.diagnostic.severity.ERROR] = "DiagnosticError",
      [vim.diagnostic.severity.WARN] = "DiagnosticWarn",
      [vim.diagnostic.severity.INFO] = "DiagnosticInfo",
      [vim.diagnostic.severity.HINT] = "DiagnosticHint",
    }
    for i, d in ipairs(diagnostics) do
      if plugin_opts.diagnostics.max_items and i > plugin_opts.diagnostics.max_items then break end
      local hl_group = hl_map[d.severity]
      if hl_group then
        local message_text = diagnostic.one_line(d.message)
        local line_text = diag_lines[i]
        if line_text and message_text and message_text ~= "" then
          local s, e = string.find(line_text, message_text, 1, true)
          if s and e then
            vim.api.nvim_buf_set_extmark(popup.bufnr, ns_id, i - 1, s - 1, {
              end_col = e,
              hl_group = hl_group,
            })
          end
        end
      end
    end
  end

  if #code_action_lines > 0 then
    local popup = make_popup(code_action_lines, width, placement.code_action_row, "Code actions", plugin_opts, placement.anchor)
    table.insert(state.popups, popup)
  end

  local keys = plugin_opts.code_actions.keys or {}
  for idx, action_tuple in ipairs(actions) do
    local key = keys[idx]
    if not key then
      break
    end

    vim.keymap.set("n", key, function ()
      M.close()
      opts.on_action(action_tuple)
    end, { buffer = state.bufnr, nowait = true, silent = true })
    table.insert(state.keymaps, key)
  end

  if plugin_opts.close.key then
    vim.keymap.set("n", plugin_opts.close.key, M.close, { buffer = state.bufnr, nowait = true, silent = true })
    table.insert(state.keymaps, plugin_opts.close.key)
  end

  vim.defer_fn(function ()
    if not M.is_open() then
      return
    end

    for _, event in ipairs(plugin_opts.close.events or {}) do
      local autocmd_id = vim.api.nvim_create_autocmd(event, {
        buffer = state.bufnr,
        callback = M.close,
      })
      table.insert(state.autocmd_ids, autocmd_id)
    end
  end,50)
end

return M
