local gpu = require("component").gpu

local util = require("/usr/ventanos/util")
local taskbar = require("/usr/ventanos/taskbar")
require("/usr/ventanos/mutex")

local toolbar_sizes = { top = 1, bottom = 0, left = 1, right = 1 }
local skin = {
	window_border = 283867,
	cross_button = 16777215,
	cross_button_background = 14961953,
	maximize_button = 16777215,
	maximize_button_background = 3893985,
	minimize_button = 16777215,
	minimize_button_background = 3893985,
	title = 16777215,
	title_background = 283867,
	tile_button = 4824101,
	title_button_background = 15641125,
	resize_button = 0,
	resize_button_background = 283867,
	tile_menu_background = 11491876,
	tile_menu_window = 2176759,
	tile_menu_secondary = 5528181,
}

---@class Window
---@field title string Title of the window
---@field redraw_handler function Handler for redrawing a window when it gets resized. Has (new_width: integer, new_heigth: integer) as arguments
---@field touch_handler function|nil Handler for window touch event. Has (x:integer, y: integer) as arguments
---@field drop_handler function|nil Handler for window drop event. Has (x: integer, y: integer) as arguments
---@field drag_handler function|nil Handler for window drag event. Has (x: integer, y: integer) as arguments
---@field key_down_handler function|nil Handler for when a key gets pressed. Has (char: number, code: number) as arguments
---@field key_up_handler function|nil Handler for when a key gets pressed. Has (char: number, code: number) as arguments
---@field maximized boolean
---@field minimized boolean
---@field thread thread
---@field geometry_lock Mutex
---@field screen_buffer integer
---@field x integer
---@field y integer
---@field width integer
---@field height integer
---@field viewport_width integer
---@field viewport_height integer
---@field background_color number
---@field background_uses_palette boolean
---@field foreground_color number
---@field foreground_uses_palette boolean
---@field palette number[]

---@type Window[]
local windows = { last = 0 }

---@type integer[]
local visible = { n = 0 } -- List of window id's ordered by visibility

local last_window_id = 1
---@return integer
local function get_new_window_id()
	while windows[last_window_id] ~= nil do
		last_window_id = last_window_id + 1
	end
	return last_window_id
end

---@param id integer
---@return integer
local function id_to_visible_index(id)
	for i = 1, visible.n do
		if visible[i] == id then
			return i
		end
	end
	error("id_to_visible_index(): No visible window with id " .. id)
end

---@param window Window
---@return integer
local function insert_window(window)
	local new_id = get_new_window_id()
	windows[new_id] = window

	for i = 1, visible.n do
		visible[i + 1] = visible[i]
	end
	visible.n = visible.n + 1

	visible[1] = new_id

	if window.screen_buffer then
		gpu.bitblt(window.screen_buffer, 1, 1, window.width, window.height, 0, window.x, window.y)
	end

	return new_id
end

---@param id integer
local function move_to_top(id)
	if windows[id].minimized then
		return
	end
	local index = id_to_visible_index(id)
	for i = 2, index, -1 do
		visible[i] = visible[i - 1]
	end
	visible[1] = index
end

---@param id integer
local function minimize(id)
	if windows[id].minimized then
		return
	end
	windows[id].minimized = true

	local index = id_to_visible_index(id)
	visible.n = visible.n - 1
	for i = index, visible.n do
		visible[i] = visible[i + 1]
	end
end

---@param id integer
local function unminimize(id)
	if not windows[id].minimized then
		return
	end
	windows[id].minimized = false

	for i = 1, visible.n do
		visible[i + 1] = visible[i]
	end
	visible.n = visible.n + 1
	visible[1] = id
end

---@param id integer
local function maximize(id)
	if windows[id].maximized then
		return
	end
	windows[id].maximized = true
end

---@param id integer
local function unmaximize(id)
	if not windows[id].maximized then
		return
	end
	windows[id].maximized = false
end

---@param id integer
---@param new_width integer
---@param new_height integer
local function set_dimensions(id, new_width, new_height)
	windows[id].width = new_width
	windows[id].height = new_height
end

---@param id integer
---@param new_x integer
---@param new_y integer
local function set_position(id, new_x, new_y)
	windows[id].x = new_x
	windows[id].y = new_y
end

---@param id integer
local function remove(id)
	minimize(id)
	if last_window_id > id then
		last_window_id = id
	end
	windows[id] = nil
end

---@param id integer
---@param new_title string
local function update_title(id, new_title)
	windows[id]["title"] = new_title
end

---@param thread thread
local function remove_all_of_thread(thread)
	local last_not_removed = 0
	for i = 1, windows.last do
		if windows[i] ~= nil then
			if windows[i].thread == thread then
				minimize(i)
				windows[i] = nil
				if last_window_id > i then
					last_window_id = i
				end
			else
				last_not_removed = i
			end
		end
	end
	windows.last = last_not_removed
end

local function remove_all()
	for i = 1, windows.last do
		if windows[i] ~= nil then
			minimize(i)
			windows[i] = nil
		end
	end
	last_window_id = 1
	windows.last = 0
end

---@return integer top
---@return integer bottom
---@return integer left
---@return integer right
local function get_toolbar_sizes()
	return toolbar_sizes.top, toolbar_sizes.bottom, toolbar_sizes.left, toolbar_sizes.right
end

--- Draws the frame of the window
---@param id integer
---@param already_locked boolean|nil If true you guarantee that the lock is already acquired
local function draw_frame(id, already_locked)
	local w = windows[id]
	if not already_locked then
		w.geometry_lock:acquire()
	end
	gpu.setBackground(skin.window_border)
	gpu.fill(w.x, w.y, w.width, 1, skin.window_border, " ")
	gpu.fill(w.x, w.y, 1, w.height, skin.window_border, " ")
	gpu.fill(w.x + w.width - 1, w.y, 1, w.height, skin.window_border, " ")

	gpu.setBackground(skin.resize_button_background)
	gpu.setForeground(skin.resize_button)
	gpu.set(w.x, w.y, "@")
	gpu.set(w.x + w.width - 1, w.y, "@")
	gpu.set(w.x, w.y + w.height - 1, "@")
	gpu.set(w.x + w.width - 1, w.y + w.height - 1, "@")

	gpu.setBackground(skin.cross_button_background)
	gpu.setForeground(skin.cross_button)
	gpu.set(w.x + w.width - 2, w.y, "X")

	gpu.setBackground(skin.maximize_button_background)
	gpu.setForeground(skin.maximize_button)
	gpu.set(w.x + w.width - 3, w.y, "■")

	gpu.setBackground(skin.minimize_button_background)
	gpu.setForeground(skin.minimize_button)
	gpu.set(w.x + w.width - 4, w.y, "_")

	gpu.setBackground(skin.title_button_background)
	gpu.setForeground(skin.tile_button)
	gpu.set(w.x + w.width - 5, w.y, "T")
	if not already_locked then
		w.geometry_lock:release()
	end
end

--- Draws the window title
---@param id integer
---@param already_locked boolean|nil If true you guarantee that the lock is already acquired
local function draw_title(id, already_locked)
	local w = windows[id]
	local _, _, left = get_toolbar_sizes()

	if not already_locked then
		w.geometry_lock:acquire()
	end

	gpu.setBackground(skin.title_background)
	gpu.setForeground(skin.title)
	if w.title:len() > w.width - left - 5 then
		gpu.set(w.x + 1, w.y, w.title:sub(1, w.width - left - 8) .. "...")
	end
	gpu.set(w.x + 1, w.y, w.title)

	if not already_locked then
		w.geometry_lock:release()
	end
end

--- Draws the window to the screen
---@param id integer
local function draw_window(id)
	draw_frame(id)
	draw_title(id)
	windows[id].geometry_lock:acquire()
	windows[id].redraw_handler()
	windows[id].geometry_lock:release()
end

local function redraw(x, y, with, heigth)
	print("Redraw called")
	--TODO:
end

local function change_geometry(id, new_x, new_y, new_width, new_heigth)
	local w = windows[id]
	if w.x == new_x and w.y == new_y and w.width == new_width and w.height == new_heigth then
		return
	end

	w.geometry_lock:acquire()

	local old_dimensions = { x = w.x, y = w.y, width = w.width, height = w.height }
	local new_dimensions = { x = new_x, y = new_y, width = new_width, height = new_heigth }

	local tmp_buffer = gpu.allocateBuffer(new_width, new_heigth)
	if tmp_buffer then
		gpu.bitblt(tmp_buffer, 1, 1, new_width, new_heigth, 0, new_x, new_y)
	end

	gpu.copy(w.x, w.y, new_width, new_heigth)

	local intersection = util.intersect(old_dimensions, new_dimensions)

	if not intersection then
		if w.screen_buffer then
			gpu.bitblt(0, w.x, w.y, w.width, w.height, w.screen_buffer, 1, 1)
			gpu.freeBuffer(w.screen_buffer)
		end
	else
		local n_rects, rects = util.subtract(old_dimensions, new_dimensions)
		if w.screen_buffer then
			for i = 1, n_rects do
				gpu.bitblt(
					0,
					rects[i].x,
					rects[i].y,
					rects[i].width,
					rects[i].height,
					w.screen_buffer,
					rects[i].x - w.x + 1,
					rects[i].y - w.y + 1
				)
			end
			gpu.freeBuffer(w.screen_buffer)
		else
			for i = 1, n_rects do
				redraw(rects[i].x, rects[i].y, rects[i].width, rects[i].height)
			end
		end
	end

	if tmp_buffer then
		w.screen_buffer = tmp_buffer
	end

	w.x = new_x
	w.y = new_y
	w.width = new_width
	w.height = new_heigth

	w.geometry_lock:release()
end

local mouse_event = { window = nil, action = nil, buffer = nil }
local function show_tile_menu()
	local x, y = gpu.getViewport()
	x = x / 2 - 7
	y = y / 2 - 4

	mouse_event.buffer = gpu.allocateBuffer(13, 7)
	if mouse_event.buffer then
		gpu.bitblt(mouse_event.buffer, 1, 1, 13, 7, 0, x, y)
	end

	gpu.setBackground(skin.tile_menu_background)
	gpu.fill(x, y, 13, 7, " ")

	gpu.setBackground(skin.tile_menu_secondary)
	for i = 1, 10, 3 do
		for j = 1, 4, 3 do
			gpu.fill(x + i, y + j, 2, 2, " ")
		end
	end

	gpu.setBackground(skin.tile_menu_window)
	gpu.fill(x + 1, y + 1, 1, 1)
	gpu.fill(x + 4, y + 1, 1, 2)
	gpu.fill(x + 7, y + 1, 2, 1)
	gpu.fill(x + 11, y + 1, 1, 1)

	gpu.fill(x + 1, y + 5, 1, 1)
	gpu.fill(x + 4, y + 4, 1, 2)
	gpu.fill(x + 7, y + 4, 2, 1)
	gpu.fill(x + 10, y + 5, 1, 1)
end

---@param event "touch"|"drop"|"drag"
---@param x number
---@param y number
local function mouse_handler(event, x, y, button)
	if mouse_event.window ~= nil then
		local id = mouse_event.window
		local w = windows[id]
		if mouse_event.action == "tile" then
			local tile_x, tile_y = gpu.getViewport()
			local full_width, full_height, half_width, half_height = tile_x, tile_y, tile_x / 2, tile_y / 2
			tile_x = tile_x / 2 - 7
			tile_y = tile_y / 2 - 4
			if event == "touch" then
				if x >= tile_x and x < tile_x + 13 and y >= tile_y and y < tile_y + 7 then
					if y >= tile_y + 1 and y <= tile_y + 2 then -- top
						if x >= tile_x + 1 and x <= tile_x + 2 then
							change_geometry(id, 1, 1, half_width, half_height)
						elseif x >= tile_x + 4 and x <= tile_x + 5 then
							change_geometry(id, 1, 1, half_width, full_height)
						elseif x >= tile_x + 7 and x <= tile_x + 8 then
							change_geometry(id, 1, 1, full_width, half_height)
						elseif x >= tile_x + 9 and x <= tile_x + 10 then
							change_geometry(id, half_width, 1, half_width, half_height)
						end
					elseif y >= tile_y + 4 and y <= tile_y + 5 then -- bottom
						if x >= tile_x + 1 and x <= tile_x + 2 then
							change_geometry(id, 1, half_height, half_width, half_height)
						elseif x >= tile_x + 4 and x <= tile_x + 5 then
							change_geometry(id, half_width, 1, half_width, full_height)
						elseif x >= tile_x + 7 and x <= tile_x + 8 then
							change_geometry(id, 1, half_height, full_width, half_height)
						elseif x >= tile_x + 9 and x <= tile_x + 10 then
							change_geometry(id, half_width, half_height, half_width, half_height)
						end
					end
				end
			end
			if mouse_event.buffer then
				gpu.bitblt(0, tile_x, tile_y, 13, 7, mouse_event.buffer, 1, 1)
				gpu.freeBuffer(mouse_event.buffer)
			else
				redraw(tile_x, tile_y, 13, 7)
			end
		elseif event == "drop" then
			mouse_event.window = nil
		elseif event == "touch" then
			goto mouse_handler_normal
		elseif mouse_event.action == "move" then
			change_geometry(mouse_event, x, y, w.width, w.height)
		elseif mouse_event.action == "resize_top_left" then
			change_geometry(id, x, y, w.width + w.x - x, w.height + w.y - y)
		elseif mouse_event.action == "resize_top_right" then
			change_geometry(id, w.x, y, w.width + x - w.x, w.height + w.y - y)
		elseif mouse_event.action == "resize_bottom_left" then
			change_geometry(id, x, w.y, w.width + x - w.x, w.height + y - w.y)
		elseif mouse_event.action == "resize_bottom_right" then
			change_geometry(id, w.x, w.y, w.width - w.x + x, w.height - w.y + y)
		end
		return
	end

	::mouse_handler_normal::

	local _, taskbar_y = gpu.getViewport()
	if y >= taskbar_y then
		taskbar.mouse_handler()
		return
	end

	for i = 1, visible.n do
		local w = windows[visible[i]]
		if x >= w.x and x < w.x + w.width and y >= w.y and y < w.y + w.height then
			if y == w.y then -- clicked on top bar
				if event == "touch" then
					if x == w.x + w.width - 1 then
						mouse_event.window = i
						mouse_event.action = "resize_top_right"
					elseif x == w.x + w.width - 2 then
						remove(i)
					elseif x == w.x + w.width - 3 then
						maximize(i)
					elseif x == w.x + w.width - 4 then
						minimize(i)
					elseif x == w.x + w.width - 5 then
						show_tile_menu()
						mouse_event.window = i
						mouse_event.action = "tile"
					elseif x == w.x then
						mouse_event.window = i
						mouse_event.action = "resize_top_left"
					else
						mouse_event.window = i
						mouse_event.action = "move"
					end
				end
			elseif x == w.x then -- click in left bar, but not in top bar
				if y == w.y + w.height - 1 then
					mouse_event.window = i
					mouse_event.action = "resize_bottom_right"
				end
			elseif x == w.x + w.width - 1 then -- click in right bar, but not in top bar
				if y == w.y + w.height - 1 then
					mouse_event.window = i
					mouse_event.action = "resize_bottom_left"
				end
			end
		end
		return
	end
end

---
---@param event "key_down"|"key_up"|"clipboard"
---@param char number|nil
---@param code number|nil
---@param clipboard string|nil
local function keyboard_handler(event, char, code, clipboard) end

return {
	insert_window = insert_window,
	move_to_top = move_to_top,
	minimize = minimize,
	unminimize = unminimize,
	maximize = maximize,
	unmaximize = unmaximize,
	set_dimensions = set_dimensions,
	set_position = set_position,
	remove = remove,
	update_title = update_title,
	remove_all = remove_all,
	remove_all_of_thread = remove_all_of_thread,
	get_toolbar_sizes = get_toolbar_sizes,
	draw_title = draw_title,
	draw_frame = draw_frame,
	draw_window = draw_window,
	mouse_handler = mouse_handler,
	keyboard_handler = keyboard_handler,
}
