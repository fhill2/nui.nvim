local buf_storage = require("nui.utils.buf_storage")
local autocmd = require("nui.utils.autocmd")
local keymap = require("nui.utils.keymap")
local defaults = require("nui.utils").defaults

local split_direction_command_map = {
  editor = {
    top = "topleft",
    right = "vertical botright",
    bottom = "botright",
    left = "vertical topleft",
  },
  win = {
    top = "aboveleft",
    right = "vertical rightbelow",
    bottom = "belowright",
    left = "vertical leftabove",
  },
}

local function init(class, options)
  local self = setmetatable({}, class)

  self.split_state = {
    mounted = false,
    loading = false,
  }

  self.split_props = {
    relative = defaults(options.relative, "win"),
    position = defaults(options.position, vim.go.splitbelow and "bottom" or "top"),
  }

  self.win_options = vim.tbl_extend("force", {
    winfixwidth = true,
  }, defaults(options.win_options, {}))

  return self
end

local Split = {
  name = "Split",
  super = nil,
}

function Split:init(options)
  return init(self, options)
end

function Split:_open_window()
  if self.winid or not self.bufnr then
    return
  end

  local props = self.split_props

  vim.api.nvim_command(
    string.format(
      "silent noswapfile %s sbuffer %s",
      split_direction_command_map[props.relative][props.position],
      self.bufnr
    )
  )

  self.winid = vim.fn.win_getid()
end

function Split:_close_window()
  if not self.winid then
    return
  end

  if vim.api.nvim_win_is_valid(self.winid) then
    vim.api.nvim_win_hide(self.winid)
  end

  self.winid = nil
end

function Split:mount()
  if self.split_state.loading or self.split_state.mounted then
    return
  end

  self.split_state.loading = true

  self.bufnr = vim.api.nvim_create_buf(false, true)
  assert(self.bufnr, "failed to create buffer")

  self:_open_window()

  self.split_state.loading = false
  self.split_state.mounted = true
end

function Split:hide()
  if self.split_state.loading or not self.split_state.mounted then
    return
  end

  self.split_state.loading = true

  self:_close_window()

  self.split_state.loading = false
end

function Split:show()
  if self.split_state.loading or not self.split_state.mounted then
    return
  end

  self.split_state.loading = true

  self:_open_window()

  self.split_state.loading = false
end

function Split:unmount()
  if self.split_state.loading or not self.split_state.mounted then
    return
  end

  self.split_state.loading = true

  buf_storage.cleanup(self.bufnr)

  if self.bufnr then
    if vim.api.nvim_buf_is_valid(self.bufnr) then
      vim.api.nvim_buf_delete(self.bufnr, { force = true })
    end
    self.bufnr = nil
  end

  if self.winid then
    if vim.api.nvim_win_is_valid(self.winid) then
      vim.api.nvim_win_close(self.winid, true)
    end
    self.winid = nil
  end

  self.split_state.loading = false
  self.split_state.mounted = false
end

-- set keymap for this split. if keymap was already set and
-- `force` is not `true` returns `false`, otherwise returns `true`
---@param mode "'i'" | "'n'"
---@param key string
---@param handler any
---@param opts table<"'expr'" | "'noremap'" | "'nowait'" | "'script'" | "'silent'" | "'unique'", boolean>
---@param force boolean
---@return boolean ok
function Split:map(mode, key, handler, opts, force)
  if not self.split_state.mounted then
    error("split is not mounted yet. call split:mount()")
  end

  return keymap.set(self.bufnr, mode, key, handler, opts, force)
end

---@param event string | string[]
---@param handler string | function
---@param options nil | table<"'once'" | "'nested'", boolean>
function Split:on(event, handler, options)
  if not self.split_state.mounted then
    error("split is not mounted yet. call split:mount()")
  end

  autocmd.buf.define(self.bufnr, event, handler, options)
end

---@param event nil | string | string[]
function Split:off(event)
  if not self.split_state.mounted then
    error("split is not mounted yet. call split:mount()")
  end

  autocmd.buf.remove(self.bufnr, nil, event)
end

local SplitClass = setmetatable({
  __index = Split,
}, {
  __call = init,
  __index = Split,
})

return SplitClass
