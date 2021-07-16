local Border = require("nui.popup.border")
local buf_storage = require("nui.utils.buf_storage")
local autocmd = require("nui.utils.autocmd")
local keymap = require("nui.utils.keymap")
local utils = require("nui.utils")
local is_type = utils.is_type

local function get_container_info(config)
  local relative = config.relative

  if relative == "editor" then
    return {
      relative = relative,
      size = utils.get_editor_size(),
      type = "editor"
    }
  end

  if relative == "cursor" or relative == "win" then
    return {
      relative = config.bufpos and "buf" or relative,
      size = utils.get_window_size(),
      type = "window",
    }
  end
end

local function calculate_window_size(size, container)
  local width
  local height

  if is_type("table", size) then
    local w = utils.parse_number_input(size.width)
    assert(w.value ~= nil, "invalid size.width")
    if w.is_percentage then
      width = math.floor(container.size.width * w.value)
    else
      width = w.value
    end

    local h = utils.parse_number_input(size.height)
    assert(h.value ~= nil, "invalid size.height")
    if h.is_percentage then
      height = math.floor(container.size.height * h.value)
    else
      height = h.value
    end
  else
    local n = utils.parse_number_input(size)
    assert(n.value ~= nil, "invalid size")
    if n.is_percentage then
      width = math.floor(container.size.width * n.value)
      height = math.floor(container.size.height * n.value)
    else
      width = n.value
      height = n.value
    end
  end

  return {
    width = width,
    height = height,
  }
end

local function calculate_window_position(position, size, container)
  local row
  local col

  local is_percentage_allowed = not vim.tbl_contains({ "buf", "cursor" }, container.relative)
  local percentage_error = string.format("position %% can not be used relative to %s", container.relative)

  if is_type("table", position) then
    local r = utils.parse_number_input(position.row)
    assert(r.value ~= nil, "invalid position.row")
    if r.is_percentage then
      assert(is_percentage_allowed, percentage_error)
      row = math.floor((container.size.height - size.height) * r.value)
    else
      row = r.value
    end

    local c = utils.parse_number_input(position.col)
    assert(c.value ~= nil, "invalid position.col")
    if c.is_percentage then
      assert(is_percentage_allowed, percentage_error)
      col = math.floor((container.size.width - size.width) * c.value)
    else
      col = c.value
    end
  else
    local n = utils.parse_number_input(position)
    assert(n.value ~= nil, "invalid position")
    if n.is_percentage then
      assert(is_percentage_allowed, percentage_error)
      row = math.floor((container.size.height - size.height) * n.value)
      col = math.floor((container.size.width - size.width) * n.value)
    else
      row = n.value
      col = n.value
    end
  end

  return {
    row = row,
    col = col,
  }
end

local function calculate_winblend(opacity)
  assert(is_type("number", opacity), "invalid opacity")
  assert(0 <= opacity, "opacity must be equal or greater than 0")
  assert(opacity <= 1, "opacity must be equal or lesser than 0")
  return 100 - (opacity * 100)
end

local function parse_padding(padding)
  if not padding then
    return nil
  end

  local map = {}
  map.top = utils.defaults(padding[1], 0)
  map.right = utils.defaults(padding[2], map.top)
  map.bottom = utils.defaults(padding[3], map.top)
  map.left = utils.defaults(padding[4], map.right)
  return map
end

local function parse_relative(relative)
  relative = utils.defaults(relative, "win")

  if is_type("string", relative) then
    relative = {
      type = utils.defaults(relative, "win")
    }
  end

  if relative.type == "win" then
    return {
      relative = relative.type,
      win = relative.winid,
    }
  end

  if relative.type == "buf" then
    return {
      relative = "win",
      bufpos = {
        relative.position.row,
        relative.position.col,
      },
    }
  end

  return {
    relative = relative.type,
  }
end

local Popup = {}

function Popup:new(opts)
  local popup = {
    config = {
      _enter = utils.defaults(opts.enter, false),
      style = "minimal",
      zindex = utils.defaults(opts.zindex, 50),
    },
    options = {
      winblend = calculate_winblend(utils.defaults(opts.opacity, 1)),
      winhighlight = opts.highlight,
    },
    padding = parse_padding(opts.padding),
    state = {
      mounted = false,
    },
  }

  popup.config = vim.tbl_extend("force", popup.config, parse_relative(opts.relative))

  setmetatable(popup, self)
  self.__index = self


  local container_info = get_container_info(popup.config)
  popup.size = calculate_window_size(opts.size, container_info)
  popup.position = calculate_window_position(opts.position, popup.size, container_info)
  popup.border = Border:new(popup, opts.border)

  popup.config.width = popup.size.width
  popup.config.height = popup.size.height
  popup.config.row = popup.position.row
  popup.config.col = popup.position.col
  popup.config.border = popup.border:get()

  if popup.config.width < 1 then
    error("width can not be negative. is padding more than width?")
  end

  if popup.config.height < 1 then
    error("height can not be negative. is padding more than height?")
  end

  return popup
end

function Popup:mount()
  if self.state.mounted then
    return
  end

  self.state.mounted = true

  self.border:mount()

  self.bufnr = vim.api.nvim_create_buf(false, true)
  assert(self.bufnr, "failed to create buffer")

  local enter = self.config._enter
  self.config._enter = nil
  self.winid = vim.api.nvim_open_win(self.bufnr, enter, self.config)
  assert(self.winid, "failed to create popup window")

  for name, value in pairs(self.options) do
    if not is_type("nil", value) then
      vim.api.nvim_win_set_option(self.winid, name, value)
    end
  end
end

function Popup:unmount()
  if not self.state.mounted then
    return
  end

  self.state.mounted = false

  self.border:unmount()

  buf_storage.cleanup(self.bufnr)

  if vim.api.nvim_buf_is_valid(self.bufnr) then
    vim.api.nvim_buf_delete(self.bufnr, { force = true })
  end

  if vim.api.nvim_win_is_valid(self.winid) then
    vim.api.nvim_win_close(self.winid, true)
  end
end

-- set keymap for this popup window. if keymap was already set and
-- `force` is not `true` returns `false`, otherwise returns `true`
---@param mode "'i'" | "'n'"
---@param key string
---@param handler any
---@param opts table<"'expr'" | "'noremap'" | "'nowait'" | "'script'" | "'silent'" | "'unique'", boolean>
---@param force boolean
---@return boolean ok
function Popup:map(mode, key, handler, opts, force)
  if not self.state.mounted then
    error("popup window is not mounted yet. call popup:mount()")
  end

  return keymap.set(self.bufnr, mode, key, handler, opts, force)
end

---@param event string | string[]
---@param handler string | function
---@param options nil | table<"'once'" | "'nested'", boolean>
function Popup:on(event, handler, options)
  autocmd.buf.define(self.bufnr, event, handler, options)
end

---@param event nil | string | string[]
function Popup:off(event)
  autocmd.buf.remove(self.bufnr, nil, event)
end

return Popup
