local gpu = require("component").gpu
local thread = require("thread")

local wm = require("ventanos_data/window_manager")
local mutex = require("ventanos_data/mutex")

---@class WindowHandle
---@field package id integer Window id
---@field package window Window

--- Changes the title of the window
---@param handle WindowHandle
---@param new_title string New title
local function setTitle(handle, new_title)
	wm.update_title(handle.id, new_title)
end

--- Kills the window
---@param handle WindowHandle
local function kill(handle)
	wm.remove(handle.id)
end

--- Sets the background color for this window like gpu.setBackground() - https://ocdoc.cil.li/component:gpu
---@param handle WindowHandle
---@param color number
---@param isPaletteIndex boolean|nil
local function setBackground(handle, color, isPaletteIndex)
	if isPaletteIndex then
		handle.window.background_color = handle.window.palette[color]
	else
		handle.window.background_color = color
	end
end

--- Sets the foreground color for this window like gpu.setForeground() - https://ocdoc.cil.li/component:gpu
---@param handle WindowHandle
---@param color number
---@param isPaletteIndex boolean|nil
local function setForeground(handle, color, isPaletteIndex)
	if isPaletteIndex then
		handle.window.foreground_color = handle.window.palette[color]
	else
		handle.window.foreground_color = color
	end
end

--- Sets a color in the palette at the specified index - https://ocdoc.cil.li/component:gpu
---@param handle WindowHandle
---@param index number
---@param value number
local function setPaletteColor(handle, index, value)
	handle.window.palette[index] = value
end

--- Prints the message
---@param handler WindowHandle
---@return boolean success Says if the operation has been completed. The operation can fail if another window is on top of the current one
---@return string reason If fails, contains the reason
local function print(handler, ...)
	return wm.window_print(handler.id, ...)
end

--- Writes a screen to the viewport starting at the specified viewport coordinates - https://ocdoc.cil.li/component:gpu
---@param handle WindowHandle
---@param x integer X coordinate of the viewport
---@param y integer Y coordinate of the viewport
---@param value string String to write
---@param vertical boolean|nil If true, print the text vertically
---@return boolean success Says if the operation has been completed. The operation can fail if another window is on top of the current one
---@return string reason If fails, contains the reason
local function set(handle, x, y, value, vertical)
	return wm.window_set(handle.id, x, y, value, vertical)
end

--- Sets the cursor position to the specified coordinates - https://ocdoc.cil.li/api:term
---@param handle WindowHandle
---@param x integer
---@param y integer
local function setCursor(handle, x, y)
	if x > 1 or y > 1 or x > handle.window.viewport_width or y > handle.window.viewport_height then
		return false
	end
	handle.window.cursor_x = x
	handle.window.cursor_y = y
end

--- Copy a portion of the viewport to another location - https://ocdoc.cil.li/component:gpu
---@param handle WindowHandle
---@param x integer X coordinate of the source rectangle
---@param y integer Y coordinate of the source rectangle
---@param width integer Width of the source rectangle
---@param height integer Height of the source rectangle
---@param tx integer X coordinate of the destination
---@param ty integer Y coordinate of the destination
---@return boolean success Says if the operation has been completed. The operation can fail if another window is on top of the current one
---@return string reason If fails, contains the reason
local function copy(handle, x, y, width, height, tx, ty)
	return wm.window_copy(handle.id, x, y, width, height, tx, ty)
end

--- Draw a rectangle - https://ocdoc.cil.li/component:gpu
---@param handle WindowHandle
---@param x integer|nil X coordinate in the viewport of the rectangle to draw
---@param y integer|nil Y coordinate in the viewport of the rectangle to draw
---@param width integer|nil Width of the rectangle to draw, if nil, the width of the window
---@param height integer|nil Height of the rectangle to draw, if nil, the height of the window
---@param char string|nil The character to draw. Must be of length one. If nil, " "
---@return boolean
---@return string reason If fails, contains the reason
local function fill(handle, x, y, width, height, char)
	return wm.window_fill(
		handle.id,
		x and x or 1,
		y and y or 1,
		width and width or handle.window.viewport_width,
		height and height or handle.window.viewport_height,
		char and char or " "
	)
end

--- Gets the current viewport resolution
---@param handle WindowHandle
---@return integer x
---@return integer y
local function getViewport(handle)
	return handle.window.viewport_width, handle.window.viewport_height
end

--- Create a new window
---@param title string Title of the window
---@param redraw_handler fun(w: WindowHandle, x: integer, y: integer, width: integer, height: integer) Handler for redrawing the window at a specific region when it is requested.
---@param touch_handler fun(w: WindowHandle, x: integer, y: integer, button: 0|1)|nil Handler for window touch event.
---@param drop_handler fun(w: WindowHandle, x: integer, y: integer, button: 0|1)|nil Handler for window drop event.
---@param drag_handler fun(w: WindowHandle, x: integer, y: integer, button: 0|1)|nil Handler for window drag event.
---@param scroll_handler fun(w: WindowHandle, x: integer, y: integer, direction: -1|1)|nil Handler for window scroll event.
---@return WindowHandle handle Handle to the new window
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

	local window_handle = setmetatable({}, {
		__index = {
			kill = kill,
			setTitle = setTitle,
			setBackground = setBackground,
			setForeground = setForeground,
			setPaletteColor = setPaletteColor,
			print = print,
			set = set,
			setCursor = setCursor,
			copy = copy,
			fill = fill,
			getViewport = getViewport,
		},
	})

	window_handle.window = w
	window_handle.id = wm.insert_window(w)

	w.environment = {}
	for i, v in pairs(_G) do
		w.environment[i] = v
	end

	w.environment.kill = function()
		return kill(window_handle)
	end
	w.environment.setTitle = function(new_title)
		return setTitle(window_handle, new_title)
	end
	w.environment.setBackground = function(color, isPaletteIndex)
		return setBackground(window_handle, color, isPaletteIndex)
	end
	w.environment.setForeground = function(color, isPaletteIndex)
		return setForeground(window_handle, color, isPaletteIndex)
	end
	w.environment.setPaletteColor = function(index, value)
		return setPaletteColor(window_handle, index, value)
	end
	w.environment.print = function(...)
		return print(window_handle, ...)
	end
	w.environment.set = function(x, y, value, vertical)
		return set(window_handle, x, y, value, vertical)
	end
	w.environment.setCursor = function(x, y)
		return setCursor(window_handle, x, y)
	end
	w.environment.copy = function(x, y, width, height, tx, ty)
		return copy(window_handle, x, y, width, height, tx, ty)
	end
	w.environment.fill = function(x, y, width, height, char)
		return fill(window_handle, x, y, width, height, char)
	end
	w.environment.getViewport = function()
		return getViewport(window_handle)
	end

	return window_handle
end

return {
	new = new,
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
}
