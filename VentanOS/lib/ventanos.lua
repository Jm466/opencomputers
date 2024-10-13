local gpu = require("component").gpu
local thread = require("thread")

local wm = require("/usr/ventanos/window_manager")
local mutex = require("/usr/ventanos/mutex")

---@class WindowHandler
---@field id integer Window id
---@field package window Window

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
	handler.window.background_color = color
	if isPaletteIndex ~= nil then
		handler.window.background_uses_palette = isPaletteIndex
	end
end

--- Sets the foreground color for this window like gpu.setForeground()
---@param handler WindowHandler
---@param color number
---@param isPaletteIndex boolean|nil
local function setForeground(handler, color, isPaletteIndex)
	handler.window.foreground_color = color
	if isPaletteIndex ~= nil then
		handler.window.foreground_uses_palette = isPaletteIndex
	end
end

--- Sets a color in the palette at the specified index
---@param handler WindowHandler
---@param index number
---@param value number
local function setPaletteColor(handler, index, value)
	handler.window.palette[index] = value
end

--- Writes a screen to the viewport starting at the specified viewport coordinates
---@param handler WindowHandler
---@param x integer X coordinate of the viewport
---@param y integer Y coordinate of the viewport
---@param value string String to write
---@param vertical boolean|nil If true, print the text vertically
local function set(handler, x, y, value, vertical)
	local w = handler.window
	local top, bottom, left, right = wm.get_toolbar_sizes()

	w.geometry_lock:acquire()

	if x > w.viewport_width or y > w.viewport_height or x < 1 or y < 1 then
		w.geometry_lock:release()
		return
	end

	if not vertical then
		local max_len = w.viewport_width - x + 1
		if max_len < 1 then
			w.geometry_lock:release()
			return
		end
		if max_len < value:len() then
			value = value:sub(1, max_len)
		end
		gpu.set(w.x + left + x, w.y + top + y, value)
	else
		local max_len = w.viewport_height - y + 1
		if max_len < 1 then
			w.geometry_lock:release()
			return
		end
		if max_len < value:len() then
			value = value:sub(1, max_len)
		end
		gpu.set(w.x + left + x, w.y + top + y, value, true)
	end

	w.geometry_lock:release()
end

--- Copy a portion of the viewport to another location
---@param handler WindowHandler
---@param x integer X coordinate of the source rectangle
---@param y integer Y coordinate of the source rectangle
---@param width integer Width of the source rectangle
---@param heigth integer Height of the source rectangle
---@param tx integer X coordinate of the destination
---@param ty integer Y coordinate of the destination
local function copy(handler, x, y, width, heigth, tx, ty)
	local w = handler.window
	local top, _, left = wm.get_toolbar_sizes()

	w.geometry_lock:acquire()

	if
		x > w.viewport_width
		or y > w.viewport_height
		or x < 1
		or y < 1
		or tx < 1
		or ty < 1
		or width < 1
		or heigth < 1
	then
		w.geometry_lock:release()
		return
	end

	local source_x = w.x + left + x - 1
	local source_y = w.y + top + y - 1

	local dest_width = width
	local dest_heigth = heigth

	if width > w.viewport_width - x + 1 then
		width = w.viewport_width - x + 1
	end
	if heigth > w.viewport_height - y + 1 then
		heigth = w.viewport_height - y + 1
	end
	if width > w.viewport_width - tx + 1 then
		dest_width = w.viewport_width - tx + 1
	end
	if heigth > w.viewport_height - ty + 1 then
		dest_heigth = w.viewport_height - y + 1
	end

	if dest_width == width and dest_heigth == heigth then
		return gpu.copy(source_x, source_y, width, heigth, tx, ty)
	else
		local buffer = gpu.allocateBuffer(width, heigth)
		if buffer == nil then
			w.geometry_lock:release()
			return false
		end
		gpu.bitblt(buffer, 1, 1, width, heigth, 0, source_x, source_y)
		gpu.bitblt(0, tx, ty, dest_width, dest_heigth, buffer, 1, 1)
		gpu.freeBuffer(buffer)
	end

	w.geometry_lock:release()
end

--- Fill a rectangle of the viewport
---@param handler WindowHandler
---@param x integer X coordinate in the viewport of the rectangle to draw
---@param y integer Y coordinate in the viewport of the rectangle to draw
---@param width integer Width of the rectangle to draw
---@param height integer Height of the rectangle to draw
---@param char string The character to draw. Must be of length one
local function fill(handler, x, y, width, height, char)
	local top, _, left = wm.get_toolbar_sizes()
	local w = handler.window

	w.geometry_lock:acquire()

	if x > w.viewport_width or y > w.viewport_height or width < 1 or height < 1 then
		w.geometry_lock:release()
		return
	end

	if width > w.viewport_width - x + 1 then
		width = w.viewport_width - x + 1
	end
	if height > w.viewport_height - x + 1 then
		height = w.viewport_height - x + 1
	end

	if width > 0 and height > 0 then
		gpu.fill(w.x + left + x, w.y + top + y, width, height, char)
	end

	w.geometry_lock:release()
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
		set = set,
		copy = copy,
		fill = fill,
		getViewport = getViewport,
	},
}

--- Create a new window
---@param title string Title of the window
---@param redraw_handler function Handler for redrawing the window when it is requested.
---@param touch_handler fun(x: integer, y: integer)|nil Handler for window touch event.
---@param drop_handler fun(x: integer, y: integer)|nil Handler for window drop event.
---@param drag_handler fun(x: integer, y: integer)|nil Handler for window drag event.
---@param key_down_handler fun(char: number, code: number)|nil Handler for when a key gets pressed.
---@param key_up_handler fun(char: number, code: number)|nil Handler for when a key gets pressed.
---@return Window window The new window
local function new(title, redraw_handler, touch_handler, drop_handler, drag_handler, key_down_handler, key_up_handler)
	local max_x, max_y = gpu.getResolution()
	local top, bottom, left, right = wm.get_toolbar_sizes()

	---@type Window
	local w
	w.title = title
	w.touch_handler = touch_handler
	w.drop_handler = drop_handler
	w.drag_handler = drag_handler
	w.redraw_handler = redraw_handler
	w.key_down_handler = key_down_handler
	w.key_up_handler = key_up_handler
	w.thread = thread.current()
	w.geometry_lock = mutex.new()
	w.maximized = false
	w.minimized = false
	w.thread = thread.current()
	w.x = math.floor(max_x * 0.15)
	w.y = math.floor(max_y * 0.15)
	w.width = math.floor(max_x * 0.6)
	w.height = math.floor(max_y * 0.6)
	w.viewport_width = w.width - left - right
	w.viewport_height = w.height - top - bottom
	w.background_color = 0
	w.background_uses_palette = false
	w.foreground_color = 16777215
	w.foreground_uses_palette = false
	w.palette = {}
	w.screen_buffer = gpu.allocateBuffer(w.width, w.height)

	setmetatable(w, metatable)

	return setmetatable({ id = wm.insert_window(w), window = w }, metatable)
end

return {
	new = new,
	setTitle = setTitle,
	kill = kill,
}
