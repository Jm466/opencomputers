local gpu = require("component").gpu
local thread = require("thread")

local util = require("ventanos_data/util")
local taskbar = require("ventanos_data/taskbar")
local background = require("ventanos_data/background")
require("ventanos_data/mutex")

local viewport_max_x, viewport_max_y = gpu.getViewport()

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
	user_crash = 16711680,
	user_crash_background = 16776960,
}

local options = {
	min_window_width = 15,
	min_window_height = 5,
}

---@class Window
---@field title string
---@field window_handler WindowHandler
---@field redraw_handler function
---@field touch_handler function|nil
---@field drop_handler function|nil
---@field drag_handler function|nil
---@field scroll_handler function|nil
---@field maximized {x: integer, y: integer, width: integer, height: integer}
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
---@field cursor_x integer
---@field cursor_y integer
---@field pending_redraws Rectangle[]

---@type Window[]
local windows = {}

---@type integer[]
local visible = {} -- List of window id's ordered by visibility

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
	for i, v in pairs(visible) do
		if v == id then
			return i
		end
	end
	util.stack_trace("id_to_visible_index(): No visible window with id " .. id)
	return 0
end

---@return integer top
---@return integer bottom
---@return integer left
---@return integer right
local function get_toolbar_sizes()
	return toolbar_sizes.top, toolbar_sizes.bottom, toolbar_sizes.left, toolbar_sizes.right
end

---@param id integer
---@param x integer
---@param y integer
---@param width integer
---@param height integer
---@return boolean
local function has_windows_on_top(id, x, y, width, height)
	local rect = { x = x, y = y, width = width, height = height }
	for i = id_to_visible_index(id) - 1, 1, -1 do
		local w = windows[i]
		if w ~= nil then
			if util.get_intersection(rect, { x = w.x, y = w.y, width = w.width, height = w.height }) then
				return true
			end
		end
	end
	return false
end

---@param w Window
local function setColorsOfClient(w)
	gpu.setForeground(w.foreground_color)
	gpu.setBackground(w.background_color)
end

--- Coordinates are absolute
---@param id integer
---@param x integer
---@param y integer
---@param width integer
---@param height integer
---@param tx integer
---@param ty integer
---@return boolean
---@return string reason
local function window_copy(id, x, y, width, height, tx, ty)
	local w = windows[id]
	local top, _, left = get_toolbar_sizes()

	if w.minimized then
		return false, "minimized"
	end

	w.geometry_lock:acquire()

	if x > w.viewport_width or y > w.viewport_height or x < 1 or y < 1 or tx + x < 1 or ty + y < 1 then
		w.geometry_lock:release()
		return false, "arguments check"
	end

	local source_x = w.x + left + x - 1
	local source_y = w.y + top + y - 1

	width = width > w.viewport_width - x + 1 and w.viewport_width - x + 1 or width
	height = height > w.viewport_height - y + 1 and w.viewport_height - y + 1 or height
	local dest_width = width > w.viewport_width - tx - x + 1 and w.viewport_width - tx - x + 1 or width
	local dest_heigth = height > w.viewport_height - ty - y + 1 and w.viewport_height - ty - y + 1 or height

	if
		width < 1
		or height < 1
		or dest_width < 1
		or dest_heigth < 1
		or has_windows_on_top(id, source_x, source_y, width, height)
		or has_windows_on_top(id, tx + source_x, ty + source_y, dest_width, dest_heigth)
	then
		w.geometry_lock:release()
		return false, "arguments check or has window on top"
	end

	if dest_width == width and dest_heigth == height then
		gpu.copy(source_x, source_y, width, height, tx, ty)
	else
		local buffer = gpu.allocateBuffer(width, height)
		if buffer == nil then
			w.geometry_lock:release()
			return false, "could not allocate a buffer"
		end
		gpu.bitblt(buffer, 1, 1, width, height, 0, source_x, source_y)
		gpu.bitblt(0, tx, ty, dest_width, dest_heigth, buffer, 1, 1)
		gpu.freeBuffer(buffer)
	end

	w.geometry_lock:release()
	return true, ""
end

---@param id integer
---@param x integer
---@param y integer
---@param width integer
---@param height integer
---@param char string
---@return boolean
---@return string reason
local function window_fill(id, x, y, width, height, char)
	local top, _, left = get_toolbar_sizes()
	local w = windows[id]

	if w.minimized then
		return false, "minimized"
	end

	w.geometry_lock:acquire()

	if x > w.viewport_width or y > w.viewport_height or width < 1 or height < 1 then
		w.geometry_lock:release()
		return false, "arguments check"
	end

	width = width > w.viewport_width - x + 1 and w.viewport_width - x + 1 or width
	height = height > w.viewport_height - y + 1 and w.viewport_height - y + 1 or height

	if has_windows_on_top(id, x, y, width, height) then
		w.geometry_lock:release()
		return false, "has window on top"
	end

	setColorsOfClient(w)
	gpu.fill(w.x + left + x - 1, w.y + top + y - 1, width, height, char)

	w.geometry_lock:release()
	return true, ""
end

---@param id integer
---@param x integer
---@param y integer
---@param value string
---@param vertical boolean|nil
---@return boolean
---@return string reason
local function window_set(id, x, y, value, vertical)
	local w = windows[id]
	local top, _, left = get_toolbar_sizes()

	if w.minimized then
		return false, "minimized"
	end

	w.geometry_lock:acquire()

	if x > w.viewport_width or y > w.viewport_height or x < 1 or y < 1 then
		w.geometry_lock:release()
		return false, "arguments check"
	end

	local start_x = w.x + left + x - 1
	local start_y = w.y + top + y - 1

	local max_len = vertical and w.viewport_height - y + 1 or w.viewport_width - x + 1
	if max_len < 1 then
		w.geometry_lock:release()
		return false, "not enough space"
	end
	if max_len < value:len() then
		value = value:sub(1, max_len)
	end

	if not vertical then
		if has_windows_on_top(id, start_x, start_y, value:len(), 1) then
			w.geometry_lock:release()
			return false, "has window on top1"
		end
		setColorsOfClient(w)
		gpu.set(start_x, start_y, value)
	else
		if has_windows_on_top(id, start_x, start_y, 1, value:len()) then
			w.geometry_lock:release()
			return false, "has window on top2"
		end
		setColorsOfClient(w)
		gpu.set(start_x, start_y, value, true)
	end

	w.geometry_lock:release()
	return true, ""
end

---@return boolean
---@return string reason
local function window_print(id, ...)
	local w = windows[id]
	local top, _, left = get_toolbar_sizes()
	local offset_x = w.x + left - 1
	local offset_y = w.y + top - 1
	local width = w.viewport_width
	local to_print

	local function check_window_on_top()
		if has_windows_on_top(id, offset_x, w.cursor_y + offset_y, width, 1) then
			w.geometry_lock:release()
			return false, "has window on top"
		end
	end

	local function line_feed()
		w.cursor_x = 1
		w.cursor_y = w.cursor_y + 1
		if w.cursor_y > w.viewport_height then
			w.cursor_y = w.viewport_height
			w.geometry_lock:release()
			local status, reason = window_copy(id, 1, 2, w.viewport_width, w.viewport_height - 1, 0, -1)
			if not status then
				return false, reason .. "(window_copy)1"
			else
				w.geometry_lock:acquire()
			end
		else
			check_window_on_top()
		end
	end

	if w.minimized then
		return false, "minimized"
	end

	local message = ""
	for _, item in pairs({ ... }) do
		message = message .. "\t" .. tostring(item)
	end
	message = message:sub(2)

	w.geometry_lock:acquire()
	setColorsOfClient(w)

	check_window_on_top()

	while message:len() > 0 do
		to_print = message:sub(1, 1)
		message = message:sub(2)

		if to_print == "\n" then
			line_feed()
		elseif to_print == "\t" then
			message = "    " .. message
		else
			gpu.set(w.cursor_x + offset_x, w.cursor_y + offset_y, to_print)
		end
		if w.cursor_x == w.viewport_width then
			line_feed()
		else
			w.cursor_x = w.cursor_x + 1
		end
	end
	line_feed()

	w.geometry_lock:release()
	return true, ""
end

---@param id integer
---@param user_function function
---@param type "handler"|"main"
local function call_userspace(id, user_function, type, ...)
	thread.create(function(...)
		local status, error = pcall(user_function, ...)
		if status then
			return error
		end

		gpu.setBackground(skin.user_crash_background)
		gpu.setForeground(skin.user_crash)

		local w = windows[id]
		local info = debug.getinfo(user_function)

		w.cursor_x = 1
		w.cursor_y = 1
		window_fill(id, 1, 1, w.viewport_width, w.viewport_height, " ")
		if type == "main" then
			window_print(id, "The application just crashed!")
		elseif type == "handler" then
			window_print(id, "A handler of the application just crashed!")
		end
		window_print(id, error)
		window_print(
			id,
			"The function was defined at: " .. tostring(info.short_src) .. ":" .. tostring(info.linedefined)
		)
		window_print(id, "Now follows all the information that could be gathered")
		for i, v in pairs(info) do
			window_print(id, tostring(i) .. "    " .. tostring(v))
		end
	end, ...)
end

--- Draws the window title
---@param id integer
local function draw_title(id)
	local w = windows[id]
	local _, _, left = get_toolbar_sizes()

	w.geometry_lock:acquire()

	gpu.setBackground(skin.title_background)
	gpu.setForeground(skin.title)
	if w.title:len() > w.width - left - 5 then
		gpu.set(w.x + 1, w.y, w.title:sub(1, w.width - left - 8) .. "...")
	end
	gpu.set(w.x + 1, w.y, w.title)

	w.geometry_lock:release()
end

--- Draws the frame of the window
---@param id integer
local function draw_frame(id)
	local w = windows[id]
	w.geometry_lock:acquire()

	gpu.setBackground(skin.window_border)
	gpu.fill(w.x, w.y, w.width, 1, " ")
	gpu.fill(w.x, w.y, 1, w.height, " ")
	gpu.fill(w.x + w.width - 1, w.y, 1, w.height, " ")

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

	w.geometry_lock:release()
end

--- Draws the window to the screen
---@param id integer
local function draw_window(id)
	draw_frame(id)
	draw_title(id)
	call_userspace(id, windows[id].redraw_handler, "handler", windows[id].window_handler)
end

local function draw_desktop()
	local visible_cpy = visible
	visible = {}

	background.draw_background(1, 1, viewport_max_x, viewport_max_y - 2)
	taskbar.draw_taskbar()

	for _, w in pairs(visible_cpy) do
		visible[1] = w
		draw_window(w)
	end

	visible = visible_cpy
end

---@param window Window
---@return integer
local function insert_window(window)
	local new_id = get_new_window_id()
	windows[new_id] = window

	for i = #visible, 1, -1 do
		visible[i + 1] = visible[i]
	end

	visible[1] = new_id

	if window.screen_buffer then
		gpu.bitblt(window.screen_buffer, 1, 1, window.width, window.height, 0, window.x, window.y)
	end

	return new_id
end

---@param id integer
---@param rects Rectangle[]
local function insert_pending_redraw(id, rects)
	local w = windows[id]
	local i = 1
	for _, rect in pairs(rects) do
		if w.pending_redraws[i] == nil then
			w.pending_redraws[id] = rect
		end
		i = i + 1
	end
end

--- Tries to redraw the regions, THE REGIONS MUST BE OUTSIDE THE WINDOW
---@param id integer
---@param regions Rectangle[]
local function try_redraw(id, regions)
	local w = windows[id]
	local start_i = id_to_visible_index(id) + 1

	---@param regs Rectangle[]
	local function redraw_under(regs)
		local i = 1
		while i <= #regs do
			local reg = regs[i]
			for w_i = start_i, #visible do
				local win = windows[w_i]
				local inter =
					util.get_intersection(reg, { x = win.x, y = win.y, width = win.width, height = win.height })
				if not inter then
					goto continue_redraw_under
				end

				call_userspace(
					id,
					win.redraw_handler,
					"handler",
					win.window_handler,
					win.x + toolbar_sizes.left + inter.x - 1,
					win.y + toolbar_sizes.top + inter.y - 1,
					inter.width,
					inter.height
				)

				regs[i] = nil

				local rest = util.subtract(reg, inter)
				if #rest > 0 then
					regs[i] = rest[1]
					for i_rest = 2, #rest do
						regs[#regs + 1] = rest[i_rest]
					end
				end

				::continue_redraw_under::
			end
			i = i + 1
		end
	end

	for i_r = 1, #regions do
		local r = regions[i_r]
		local region_r = { x = r.x, y = r.y, width = r.width, height = r.height }
		for i_p = 1, #w.pending_redraws do
			local p = w.pending_redraws[i_p]
			local inter = util.get_intersection(region_r, { x = p.x, y = p.y, width = p.width, height = p.height })
			if inter and not has_windows_on_top(id, r.x, r.y, r.width, r.height) then
				redraw_under({ inter })

				w.pending_redraws[i_p] = nil
				insert_pending_redraw(id, util.subtract(region_r, inter))
			end
		end
	end
end

--- Coordinates absolute. Marks a region that needs to be drawn when the window moves out of that region
---@param id integer
---@param x integer
---@param y integer
---@param width integer
---@param height integer
local function redraw(id, x, y, width, height)
	local w = windows[id]
	---@type Rectangle[]
	local regions_to_add = { { x = x, y = y, width = width, height = height } }
	local regions_to_add_idx = 1

	while regions_to_add_idx <= #regions_to_add do
		for i = 1, #w.pending_redraws do
			local regions = util.subtract(regions_to_add[i], w.pending_redraws[i])
			if #regions > 0 then
				regions_to_add[i] = regions[1]
				for i_reg = 2, #regions do
					regions_to_add[#regions_to_add + 1] = regions[i_reg]
				end
			else
				i = i + 1
			end
		end
	end

	insert_pending_redraw(id, regions_to_add)
end

---@param id integer
local function move_to_top(id)
	local w = windows[id]
	if w.minimized then
		return
	end

	local index = id_to_visible_index(id)

	if index == 1 then
		return
	end

	local rect = { x = w.x, y = w.y, width = w.width, height = w.height }

	if not w.screen_buffer then
		for i = index - 1, 1, -1 do
			local win = windows[visible[i]]
			if win ~= nil then
				local inter =
					util.get_intersection(rect, { x = win.x, y = win.y, width = win.width, height = win.height })
				if inter ~= nil then
					redraw(id, inter.x, inter.y, inter.width, inter.height)
				end
			end
		end
		for i = index, 2, -1 do
			visible[i] = visible[i + 1]
		end
		visible[1] = id
		call_userspace(id, w.redraw_handler, "handler", w.window_handler)
		return
	end

	w.geometry_lock:acquire()
	local final_buffer = gpu.allocateBuffer(w.width, w.height)
	local final_buffer_regions = {} ---@type Rectangle[]
	local last_region ---@type integer

	for i = index - 1, 1, -1 do
		local win = windows[visible[i]]
		if win ~= nil then
			local inter = util.get_intersection(rect, { x = win.x, y = win.y, width = win.width, height = win.height })
			if inter ~= nil then
				win.geometry_lock:acquire()
				if win.screen_buffer then
					if final_buffer then
						gpu.bitblt(
							final_buffer,
							inter.x - win.x + 1,
							inter.y - win.y + 1,
							inter.width,
							inter.height,
							win.screen_buffer,
							inter.x - win.x + 1,
							inter.y - win.y + 1
						)
						gpu.bitblt(
							win.screen_buffer,
							inter.x - win.x + 1,
							inter.y - win.y + 1,
							inter.width,
							inter.height,
							w.screen_buffer,
							inter.x - w.x + 1,
							inter.y - w.y + 1
						)
						last_region = #final_buffer_regions + 1
						final_buffer_regions[last_region] = inter
					else -- No tmp_buffer
						gpu.bitblt(
							w.screen_buffer,
							inter.x - w.x + 1,
							inter.y - w.y + 1,
							inter.width,
							inter.height,
							win.screen_buffer,
							inter.x - win.x + 1,
							inter.y - win.y + 1
						)
						redraw(i, inter.x, inter.y, inter.width, inter.height)
					end
				else -- No screen_buffer for win
					redraw(id, inter.x, inter.y, inter.width, inter.height)
				end
				win.geometry_lock:release()
			end
		end
	end

	w.geometry_lock:release()

	for i = index, 2, -1 do
		visible[i] = visible[i - 1]
	end
	visible[1] = id
end

---@param id integer
local function minimize(id)
	local w = windows[id]
	if w.minimized then
		return
	end
	w.minimized = true

	if w.screen_buffer then
		gpu.bitblt(0, w.x, w.y, w.width, w.height, w.screen_buffer, 1, 1)
	else
		redraw(id, w.x, w.y, w.width, w.height)
		try_redraw(id, { x = w.x, y = w.y, width = w.width, height = w.height })
	end

	local index = id_to_visible_index(id)
	for i = index, #visible do
		visible[i] = visible[i + 1]
	end
end

---@param id integer
local function unminimize(id)
	if not windows[id].minimized then
		return
	end
	windows[id].minimized = false

	for i = 1, #visible do
		visible[i + 1] = visible[i]
	end
	visible[1] = id
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
	draw_frame(id)
	draw_title(id)
end

---@param t thread
local function remove_all_of_thread(t)
	for i = 1, #windows do
		if windows[i] ~= nil then
			if windows[i].thread == t then
				remove(i)
			end
		end
	end
end

local function remove_all()
	for i = 1, #windows do
		if windows[i] ~= nil then
			remove(i)
		end
	end
end

---@param id integer
---@param new_x integer
---@param new_y integer
---@param new_width integer
---@param new_height integer
local function change_geometry(id, new_x, new_y, new_width, new_height)
	local w = windows[id]
	if w.x == new_x and w.y == new_y and w.width == new_width and w.height == new_height then
		return
	end

	new_width = new_width < options.min_window_width and options.min_window_width or new_width
	new_height = new_height < options.min_window_height and options.min_window_height or new_height
	new_y = new_y + new_height - 1 > viewport_max_x - 2 and viewport_max_y - new_height - 1 or new_y
	new_y = new_y < 1 and 1 or new_y

	w.geometry_lock:acquire()

	local old_dimensions = { x = w.x, y = w.y, width = w.width, height = w.height }
	local new_dimensions = { x = new_x, y = new_y, width = new_width, height = new_height }

	local tmp_buffer = gpu.allocateBuffer(new_width, new_height)
	if tmp_buffer then
		gpu.bitblt(tmp_buffer, 1, 1, new_width, new_height, 0, new_x, new_y)
	end

	gpu.copy(w.x, w.y, new_width, new_height, new_x - w.x, new_y - w.y)

	local intersection = util.get_intersection(old_dimensions, new_dimensions)

	if not intersection then
		if w.screen_buffer then
			gpu.bitblt(0, w.x, w.y, w.width, w.height, w.screen_buffer, 1, 1)
			gpu.freeBuffer(w.screen_buffer)
		else --TODO:
		end
	else
		local rects = util.subtract(old_dimensions, new_dimensions)
		if w.screen_buffer then
			for _, rect in pairs(rects) do
				gpu.bitblt(
					0,
					rect.x,
					rect.y,
					rect.width,
					rect.height,
					w.screen_buffer,
					rect.x - w.x + 1,
					rect.y - w.y + 1
				)
			end
			gpu.bitblt(
				tmp_buffer,
				w.x - new_x + 1 > 0 and w.x - new_x + 1 or 1,
				w.y - new_y + 1 > 0 and w.y - new_y + 1 or 1,
				intersection.width,
				intersection.height,
				w.screen_buffer,
				intersection.x - w.x + 1,
				intersection.y - w.y + 1
			)
			gpu.freeBuffer(w.screen_buffer)
		else
			for _, rect in pairs(rects) do
				redraw(id, rect.x, rect.y, rect.width, rect.height)
			end
		end
		try_redraw(id, rects)
	end

	if tmp_buffer then
		w.screen_buffer = tmp_buffer
	end

	local top, bottom, left, right = get_toolbar_sizes()

	w.x = new_x
	w.y = new_y
	w.width = new_width
	w.height = new_height
	w.viewport_width = w.width - left - right
	w.viewport_height = w.height - top - bottom

	w.geometry_lock:release()
end

---@param id integer
local function maximize(id)
	local w = windows[id]
	local max_y = viewport_max_y - 2

	if w.maximized then
		return
	end

	w.maximized = { x = w.x, y = w.y, width = w.width, height = w.height }
	change_geometry(id, 1, 1, viewport_max_x, max_y)
	draw_window(id)
end

---@param id integer
local function unmaximize(id)
	local w = windows[id]
	if not w.maximized then
		return
	end
	change_geometry(id, w.maximized.x, w.maximized.y, w.maximized.width, w.maximized.height)
	w.maximized = nil
	draw_window(id)
end

local mouse_event = { window = nil, action = nil, buffer = nil, previous = { x = 0, y = 0 } }
local function show_tile_menu()
	local x = viewport_max_x / 2 - 13
	local y = viewport_max_y / 2 - 4

	mouse_event.buffer = gpu.allocateBuffer(26, 7)
	if mouse_event.buffer then
		gpu.bitblt(mouse_event.buffer, 1, 1, 26, 7, 0, x, y)
	end

	gpu.setBackground(skin.tile_menu_background)
	gpu.fill(x, y, 26, 7, " ")

	gpu.setBackground(skin.tile_menu_secondary)
	for i = 2, 20, 6 do
		for j = 1, 4, 3 do
			gpu.fill(x + i, y + j, 4, 2, " ")
		end
	end

	gpu.setBackground(skin.tile_menu_window)
	gpu.fill(x + 2, y + 1, 2, 1, " ")
	gpu.fill(x + 8, y + 1, 2, 2, " ")
	gpu.fill(x + 14, y + 1, 4, 1, " ")
	gpu.fill(x + 22, y + 1, 2, 1, " ")

	gpu.fill(x + 2, y + 5, 2, 1, " ")
	gpu.fill(x + 10, y + 4, 2, 2, " ")
	gpu.fill(x + 14, y + 5, 4, 1, " ")
	gpu.fill(x + 22, y + 5, 2, 1, " ")
end

---@param event "touch"|"drop"|"drag"|"scroll"
---@param x number
---@param y number
local function mouse_event_handler(event, x, y)
	---@type integer
	local id = mouse_event.window

	local w = windows[id]
	local offset_x = x - mouse_event.previous.x
	local offset_y = y - mouse_event.previous.y

	if w.maximized then
		unmaximize(id)
	end

	if event == "scroll" then
		return
	end

	if mouse_event.action == "tile" then
		if event == "touch" then
			local half_width, half_height = viewport_max_x / 2, viewport_max_y / 2 - 1
			local tile_x = viewport_max_x / 2 - 13
			local tile_y = viewport_max_y / 2 - 4

			if mouse_event.buffer then
				gpu.bitblt(0, tile_x, tile_y, 26, 7, mouse_event.buffer, 1, 1)
				gpu.freeBuffer(mouse_event.buffer)
			else
				redraw(1, tile_x, tile_y, 26, 7)
				try_redraw(1, { x = tile_x, y = tile_y, width = 26, height = 7 })
			end
			mouse_event.window = nil

			if x >= tile_x and x < tile_x + 26 and y >= tile_y and y < tile_y + 7 then
				if y >= tile_y + 1 and y <= tile_y + 2 then
					if x >= tile_x + 2 and x <= tile_x + 5 then -- top left
						change_geometry(id, 1, 1, half_width, half_height)
						draw_window(id)
					elseif x >= tile_x + 8 and x <= tile_x + 11 then -- full left
						change_geometry(id, 1, 1, half_width, viewport_max_y)
						draw_window(id)
					elseif x >= tile_x + 14 and x <= tile_x + 17 then -- full top
						change_geometry(id, 1, 1, viewport_max_x, half_height)
						draw_window(id)
					elseif x >= tile_x + 20 and x <= tile_x + 23 then -- top right
						change_geometry(id, half_width + 1, 1, half_width, half_height)
						draw_window(id)
					end
				elseif y >= tile_y + 4 and y <= tile_y + 5 then
					if x >= tile_x + 2 and x <= tile_x + 5 then -- bottom left
						change_geometry(id, 1, half_height + 1, half_width, half_height)
						draw_window(id)
					elseif x >= tile_x + 8 and x <= tile_x + 11 then -- full right
						change_geometry(id, half_width + 1, 1, half_width, viewport_max_y)
						draw_window(id)
					elseif x >= tile_x + 14 and x <= tile_x + 17 then -- full bottom
						change_geometry(id, 1, half_height + 1, viewport_max_x, half_height)
						draw_window(id)
					elseif x >= tile_x + 20 and x <= tile_x + 23 then -- bottom right
						change_geometry(id, half_width + 1, half_height + 1, half_width, half_height)
						draw_window(id)
					end
				end
			end
		end
		return
	elseif mouse_event.action == "move" then
		change_geometry(id, w.x + offset_x, w.y + offset_y, w.width, w.height)
	elseif mouse_event.action == "resize_top_left" then
		change_geometry(id, x, y, w.width - offset_x, w.height - offset_y)
	elseif mouse_event.action == "resize_top_right" then
		change_geometry(id, w.x, y, w.width + offset_x, w.height - offset_y)
	elseif mouse_event.action == "resize_bottom_left" then
		change_geometry(id, x, w.y, w.width - offset_x, w.height + offset_y)
	elseif mouse_event.action == "resize_bottom_right" then
		change_geometry(id, w.x, w.y, w.width + offset_x, w.height + offset_y)
	end
	if event == "drop" then
		mouse_event.window = nil
		draw_window(id)
	else
		draw_frame(id)
	end
	mouse_event.previous.x = x
	mouse_event.previous.y = y
end

---@param event "touch"|"drop"|"drag"|"scroll"
---@param x number
---@param y number
---@param button 0|1
---@param scroll -1|1
local function mouse_handler(event, x, y, button, scroll)
	if mouse_event.window ~= nil and event ~= "scroll" and (event ~= "touch" or mouse_event.action == "tile") then
		mouse_event_handler(event, x, y)
		return
	end

	if y > viewport_max_y - 2 then
		taskbar.mouse_handler(event, x, y)
		return
	end

	for i = 1, #visible do
		local id = visible[i]
		local w = windows[id]
		if x >= w.x and x < w.x + w.width and y >= w.y and y < w.y + w.height then
			local top, bottom, left, _ = get_toolbar_sizes()
			if id ~= 1 then
				move_to_top(id)
				draw_window(id)
			end

			if y == w.y then -- clicked on top bar
				if event == "touch" then
					mouse_event.previous.x = x
					mouse_event.previous.y = y
					if x == w.x + w.width - 1 then
						mouse_event.window = id
						mouse_event.action = "resize_top_right"
					elseif x == w.x + w.width - 2 then
						remove(i)
					elseif x == w.x + w.width - 3 then
						if w.maximized then
							unmaximize(i)
						else
							maximize(i)
						end
					elseif x == w.x + w.width - 4 then
						--minimize(i) TODO: The taskbar needs to be implemented
					elseif x == w.x + w.width - 5 then
						mouse_event.window = id
						mouse_event.action = "tile"
						show_tile_menu()
					elseif x == w.x then
						mouse_event.window = id
						mouse_event.action = "resize_top_left"
					else
						mouse_event.window = id
						mouse_event.action = "move"
					end
				end
			elseif x == w.x then -- click in left bar, but not in top bar
				if event == "touch" and y == w.y + w.height - 1 then
					mouse_event.window = id
					mouse_event.action = "resize_bottom_left"
					mouse_event.previous.x = x
					mouse_event.previous.y = y
				end
			elseif x == w.x + w.width - 1 then -- click in right bar, but not in top bar
				if event == "touch" and y == w.y + w.height - 1 then
					mouse_event.window = id
					mouse_event.action = "resize_bottom_right"
					mouse_event.previous.x = x
					mouse_event.previous.y = y
				end
			elseif x >= w.x + left and x <= w.x + w.width - left and y >= w.y + top and y < w.y + w.height - bottom then
				local user_x, user_y = x - w.x + left - 1, y - w.y + top - 1
				if event == "touch" and w.touch_handler then
					call_userspace(id, w.touch_handler, "handler", w.window_handler, user_x, user_y, button)
				elseif event == "drag" and w.drag_handler then
					call_userspace(id, w.drag_handler, "handler", w.window_handler, user_x, user_y, button)
				elseif event == "drop" and w.drop_handler then
					call_userspace(id, w.drop_handler, "handler", w.window_handler, user_x, user_y, button)
				elseif event == "scroll" and w.scroll_handler then
					call_userspace(id, w.scroll_handler, "handler", w.window_handler, user_x, user_y, scroll)
				end
			end
			return
		end
	end
end

return {
	insert_window = insert_window,
	move_to_top = move_to_top,
	minimize = minimize,
	unminimize = unminimize,
	maximize = maximize,
	unmaximize = unmaximize,
	remove = remove,
	update_title = update_title,
	remove_all = remove_all,
	remove_all_of_thread = remove_all_of_thread,
	get_toolbar_sizes = get_toolbar_sizes,
	draw_title = draw_title,
	draw_frame = draw_frame,
	draw_window = draw_window,
	mouse_handler = mouse_handler,
	call_userspace = call_userspace,
	print = print,
	window_set = window_set,
	window_copy = window_copy,
	window_fill = window_fill,
	window_print = window_print,
	draw_desktop = draw_desktop,
}