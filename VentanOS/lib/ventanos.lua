local gpu = require("component").gpu
local thread = require("thread")

local wm = require("ventanos_data/window_manager")
local mutex = require("ventanos_data/mutex")

---@class WindowHandler
---@field id integer Window id
---@field package window Window
---@field kill fun(handler: WindowHandler) Kills the window
---@field setTitle fun(handler: WindowHandler, new_title: string) Sets the title of the window
---@field setBackground fun(handler: WindowHandler, color: number, isPaletteIndex: boolean|nil) see setBackground at https://ocdoc.cil.li/component:gpu
---@field setForeground fun(handler: WindowHandler, color: number, isPaletteIndex: boolean|nil) see setForeground at https://ocdoc.cil.li/component:gpu
---@field setPaletteColor fun(handler: WindowHandler, index: number, value: number ) see setPalletteColor at https://ocdoc.cil.li/component:gpu
---@field print fun(handle: WindowHandler, ...) see https://www.lua.org/manual/5.2/manual.html#pdf-print
---@field set fun(handler: WindowHandler, x: integer, y: integer, value: string, vertical: boolean|nil) see gpu.set() at  https://ocdoc.cil.li/component:gpu
---@field copy fun(handler: WindowHandler, x: integer, y: integer, width: integer, height: integer, tx: integer, ty: integer) see copy() at https://ocdoc.cil.li/component:gpu
---@field fill fun(handler: WindowHandler, x: integer, y: integer, width: integer|nil, height: integer|nil, char: string|nil) see set() at https://ocdoc.cil.li/component:gpu   If width or height are nil, the width and height of the window will be used respectively; if char is nil, " " will be used
---@field setCursor fun(handler: WindowHandler, x: integer, y: integer)
---@field getViewport fun(handler: WindowHandler)

--- Changes the title of the window
---@param window WindowHandler
---@param new_title string New title
local function setTitle(window, new_title)
	wm.update_title(window.id, new_title)
end

--- Kills a window
---@param window WindowHandler
local function kill(window)
	wm.kill(window.id)
end

--- Sets the background color for this window like gpu.setBackground()
---@param handler WindowHandler
---@param color number
---@param isPaletteIndex boolean|nil
local function setBackground(handler, color, isPaletteIndex)
	if isPaletteIndex then
		handler.window.background_color = handler.window.palette[color]
	else
		handler.window.background_color = color
	end
end

--- Sets the foreground color for this window like gpu.setForeground()
---@param handler WindowHandler
---@param color number
---@param isPaletteIndex boolean|nil
local function setForeground(handler, color, isPaletteIndex)
	if isPaletteIndex then
		handler.window.foreground_color = handler.window.palette[color]
	else
		handler.window.foreground_color = color
	end
end

--- Sets a color in the palette at the specified index
---@param handler WindowHandler
---@param index number
---@param value number
local function setPaletteColor(handler, index, value)
	handler.window.palette[index] = value
end

--- Prints the message
---@param handler WindowHandler
---@return boolean success Says if the operation has been completed. The operation can fail if another window is on top of the current one
---@return string reason If fails, contains the reason
local function print(handler, ...)
	return wm.window_print(handler.id, ...)
end

--- Writes a screen to the viewport starting at the specified viewport coordinates
---@param handler WindowHandler
---@param x integer X coordinate of the viewport
---@param y integer Y coordinate of the viewport
---@param value string String to write
---@param vertical boolean|nil If true, print the text vertically
---@return boolean success Says if the operation has been completed. The operation can fail if another window is on top of the current one
---@return string reason If fails, contains the reason
local function set(handler, x, y, value, vertical)
	return wm.window_set(handler.id, x, y, value, vertical)
end

---@param handler WindowHandler
---@param x integer
---@param y integer
local function setCursor(handler, x, y)
	if x > 1 or y > 1 or x > handler.window.viewport_width or y > handler.window.viewport_height then
		return false
	end
	handler.window.cursor_x = x
	handler.window.cursor_y = y
end

--- Copy a portion of the viewport to another location
---@param handler WindowHandler
---@param x integer X coordinate of the source rectangle
---@param y integer Y coordinate of the source rectangle
---@param width integer Width of the source rectangle
---@param height integer Height of the source rectangle
---@param tx integer X coordinate of the destination
---@param ty integer Y coordinate of the destination
---@return boolean success Says if the operation has been completed. The operation can fail if another window is on top of the current one
---@return string reason If fails, contains the reason
local function copy(handler, x, y, width, height, tx, ty)
	return wm.window_copy(handler.id, x, y, width, height, tx, ty)
end

--- Fill a rectangle of the viewport
---@param handler WindowHandler
---@param x integer X coordinate in the viewport of the rectangle to draw
---@param y integer Y coordinate in the viewport of the rectangle to draw
---@param width integer|nil Width of the rectangle to draw, if nil, the width of the window
---@param height integer|nil Height of the rectangle to draw, if nil, the height of the window
---@param char string|nil The character to draw. Must be of length one. If nil, " "
---@return boolean
---@return string reason If fails, contains the reason
local function fill(handler, x, y, width, height, char)
	return wm.window_fill(
		handler.id,
		x,
		y,
		width and width or handler.window.viewport_width,
		height and height or handler.window.viewport_height,
		char and char or " "
	)
end

--- Gets the current viewport resolution
---@param handler WindowHandler
---@return integer x
---@return integer y
local function getViewport(handler)
	return handler.window.viewport_width, handler.window.viewport_height
end

local metatable = {
	__index = {
		kill = kill,
		setTitle = setTitle,
		setBackground = setBackground,
		setForeground = setForeground,
		setPaletteColor = setPaletteColor,
		print = print,
		set = set,
		copy = copy,
		fill = fill,
		getViewport = getViewport,
		setCursor = setCursor,
	},
}

--- Create a new window
---@param title string Title of the window
---@param redraw_handler fun(w: WindowHandler, x: integer, y: integer, width: integer, height: integer) Handler for redrawing the window at a specific region when it is requested.
---@param touch_handler fun(w: WindowHandler, x: integer, y: integer, button: 0|1)|nil Handler for window touch event.
---@param drop_handler fun(w: WindowHandler, x: integer, y: integer, button: 0|1)|nil Handler for window drop event.
---@param drag_handler fun(w: WindowHandler, x: integer, y: integer, button: 0|1)|nil Handler for window drag event.
---@param scroll_handler fun(w: WindowHandler, x: integer, y: integer, direction: -1|1)|nil Handler for window scroll event.
---@return WindowHandler window The new window
local function new(title, redraw_handler, touch_handler, drop_handler, drag_handler, scroll_handler)
	local max_x, max_y = gpu.getResolution()
	local top, bottom, left, right = wm.get_toolbar_sizes()

	---@type Window
	---@diagnostic disable-next-line: missing-fields
	local w = {}
	w.title = title
	w.touch_handler = touch_handler
	w.drop_handler = drop_handler
	w.drag_handler = drag_handler
	w.redraw_handler = redraw_handler
	w.scroll_handler = scroll_handler
	w.thread = thread.current()
	w.geometry_lock = mutex.new_mutex()
	w.maximized = nil
	w.minimized = false
	w.x = math.floor(max_x * 0.15)
	w.y = math.floor(max_y * 0.15)
	w.width = math.floor(max_x * 0.4)
	w.height = math.floor(max_y * 0.4)
	w.viewport_width = w.width - left - right
	w.viewport_height = w.height - top - bottom
	w.background_color = 0
	w.background_uses_palette = false
	w.foreground_color = 16777215
	w.foreground_uses_palette = false
	w.palette = {}
	w.screen_buffer = gpu.allocateBuffer(w.width, w.height)
	w.cursor_x = 1
	w.cursor_y = 1
	w.pending_redraws = {}
	w.window_handler = setmetatable({}, metatable)

	setmetatable(w, metatable)

	w.window_handler.window = w
	w.window_handler.id = wm.insert_window(w)

	return w.window_handler
end

return { new = new }
