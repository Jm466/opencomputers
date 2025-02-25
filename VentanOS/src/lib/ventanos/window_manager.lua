local gpu = require("component").gpu
local thread = require("thread")
local shell = require("shell")

local util = require("ventanos/util")
local taskbar = require("ventanos/taskbar")
local background = require("ventanos/background")

local viewport_max_x, viewport_max_y = gpu.getViewport()
local max_memory = tostring(math.floor(gpu.totalMemory()))

local window_border_sizes = { top = 1, bottom = 0, left = 1, right = 1 }
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
	memory = 0xFFFFFF,
}

local options = {
	min_window_width = 15,
	min_window_height = 5,
	debug = false,
}

---@class Window
---@field title string
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
---@field workdir string

---@type Window[]
local windows = {} -- Unordered list that contains all the windows

---@type integer[]
local visible = {} -- List of window id's ordered by visibility(the first one is on top of the rest, the second one is on top of everyone but the first and so on)

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

	local vw_str = "["
	for _, v in pairs(visible) do
		vw_str = vw_str .. v .. ", "
	end

	vw_str = vw_str:sub(1, vw_str:len() - 2) .. "]"

	error("id_to_visible_index(): No visible window with id " .. id .. ", visible windows: " .. vw_str)
	return 0
end

local function id_to_window(id)
	local w = windows[id]
	if w ~= nil then
		return w
	end

	local w_str = "["
	for _, v in pairs(windows) do
		w_str = w_str .. "{" .. v.title .. "," .. v.x .. "," .. v.y .. "}" .. ", "
	end

	w_str = w_str:sub(1, w_str:len() - 2) .. "]"
	error("id_to_window(): No window with id " .. id .. ", windows: " .. w_str)
end

local function print_debug_info()
	local max_x = gpu.getViewport()
	max_x = max_x - 1
	local start_x = max_x - 50
	local idx = 2

	gpu.fill(start_x, idx, max_x - start_x + 1, 10, " ")

	gpu.set(start_x, idx, " --- Visible ---")

	for i, v in pairs(visible) do
		idx = idx + 1
		gpu.set(start_x, idx, tostring(i) .. "º: window " .. tostring(v))
	end

	idx = idx + 1
	gpu.set(start_x, idx, " --- Windows ---")

	for i, v in pairs(windows) do
		idx = idx + 1
		gpu.set(
			start_x,
			idx,
			"window " .. tostring(i) .. ": " .. v.title .. " at " .. tostring(v.x) .. "," .. tostring(v.y)
		)
	end
end

---@return integer top
---@return integer bottom
---@return integer left
---@return integer right
local function get_window_border_sizes()
	return window_border_sizes.top, window_border_sizes.bottom, window_border_sizes.left, window_border_sizes.right
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
		local w = id_to_window(i)
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
	local w = id_to_window(id)
	local top, _, left = get_window_border_sizes()

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
	local top, _, left = get_window_border_sizes()
	local w = id_to_window(id)

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
	local w = id_to_window(id)
	local top, _, left = get_window_border_sizes()

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
	local w = id_to_window(id)
	local top, _, left = get_window_border_sizes()
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

	local function check_scroll()
		if w.cursor_y > w.viewport_height then
			w.cursor_y = w.viewport_height
			w.geometry_lock:release()
			local status, reason = window_copy(id, 1, 2, w.viewport_width, w.viewport_height - 1, 0, -1)
			if not status then
				return false, reason .. "(window_copy)1"
			end
			status, reason = window_fill(id, 1, w.viewport_height, w.viewport_width, 1, " ")
			if not status then
				return false, reason .. "(window_fill)"
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

	check_scroll()

	local beeped = false

	while message:len() > 0 do
		to_print = message:sub(1, 1)
		message = message:sub(2)

		if to_print == "\n" then
			w.cursor_x = 1
			w.cursor_y = w.cursor_y + 1
			check_scroll()
		elseif to_print == "\t" then
			w.cursor_x = ((w.cursor_x - 1) - ((w.cursor_x - 1) % 8)) + 9
		elseif to_print == "\r" then
			w.cursor_x = 1
		elseif to_print == "\b" then
			w.cursor_x = w.cursor_x - 1
		elseif to_print == "\v" then
			w.cursor_y = w.cursor_y + 1
			check_scroll()
		elseif to_print == "\a" and not beeped then
			require("computer").beep()
			beeped = true
		else
			gpu.set(w.cursor_x + offset_x, w.cursor_y + offset_y, to_print)
		end
		if w.cursor_x == w.viewport_width then
			w.cursor_x = 1
			w.cursor_y = w.cursor_y + 1
			check_scroll()
		else
			w.cursor_x = w.cursor_x + 1
		end
	end
	w.cursor_x = 1
	w.cursor_y = w.cursor_y + 1

	w.geometry_lock:release()
	return true, ""
end

local function draw_memory()
	gpu.setBackground(2316495)
	gpu.setForeground(skin.memory)
	local x = viewport_max_x - 15
	gpu.fill(x, viewport_max_y, 15, 1, " ")
	gpu.set(x, viewport_max_y, tostring(math.floor(gpu.freeMemory())) .. "/" .. max_memory .. "Bytes")
end

--- Draws the window title
---@param id integer
local function draw_title(id)
	local w = id_to_window(id)
	local _, _, left = get_window_border_sizes()

	w.geometry_lock:acquire()

	gpu.setBackground(skin.title_background)
	gpu.setForeground(skin.title)

	local title = w.title

	if options.debug then
		title = "(" .. id .. ")" .. w.title
	end

	if w.title:len() > w.width - left - 5 then
		title = w.title:sub(1, w.width - left - 8) .. "..."
	end

	gpu.set(w.x + 1, w.y, title)

	w.geometry_lock:release()
end

--- Draws the frame of the window
---@param id integer
local function draw_frame(id)
	local w = id_to_window(id)
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

local call_userspace
--- Draws the window to the screen
---@param id integer
local function draw_window(id)
	draw_frame(id)
	draw_title(id)
	call_userspace(id, id_to_window(id).redraw_handler, "handler")
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
---@param id integer
---@param new_title string
local function update_title(id, new_title)
	id_to_window(id).title = new_title
	draw_frame(id)
	draw_title(id)
end

---@param id integer
---@param user_function function
---@param call_type "handler"|"main"|"internal"|"program_load"
function call_userspace(id, user_function, call_type, ...)
	local status, error

	if type(user_function) ~= "function" then
		if call_type == "program_load" then
			return false, "Posibly failed to parse init.lua, does init.lua contain any errors?"
		end
		return false, "invalid user_function"
	end

	local child = thread.create(function(...)
		local w = id_to_window(id)

		local old_workdir = shell.getWorkingDirectory()
		shell.setWorkingDirectory(w.workdir)

		local c = coroutine.create(user_function)
		status, error = coroutine.resume(c, ...)

		shell.setWorkingDirectory(old_workdir)

		if status then
			return
		end

		local trace = debug.traceback(c, error)

		if w.geometry_lock:is_locked() then
			w.geometry_lock:release()
		end

		w.touch_handler = nil
		w.drop_handler = nil
		w.drag_handler = nil
		w.scroll_handler = nil
		w.redraw_handler = function()
			w.background_color = skin.user_crash_background
			w.foreground_color = skin.user_crash
			w.cursor_x = 1
			w.cursor_y = 1

			window_fill(id, 1, 1, w.viewport_width, w.viewport_height, " ")
			if call_type == "main" then
				window_print(id, "The application just crashed!")
			elseif call_type == "handler" then
				window_print(id, "A handler of the application just crashed!")
			elseif call_type == "internal" then
				window_print(id, "VentanOS error!")
			elseif call_type == "program_load" then
				window_print(id, "init.lua crashed while loading!")
			end

			window_print(id, trace)
		end

		update_title(id, "Kaboom!")
		w.redraw_handler()
	end, ...)

	if call_type == "program_load" then
		child:join()
		return status, error
	end
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
	local w = id_to_window(id)
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
	if true then -- TODO:
		return
	end
	local w = id_to_window(id)
	local start_i = id_to_visible_index(id) + 1

	---@param regs Rectangle[]
	local function redraw_under(regs)
		local i = 1
		while i <= #regs do
			local reg = regs[i]
			for w_i = start_i, #visible do
				local win = id_to_window(w_i)
				local inter =
					util.get_intersection(reg, { x = win.x, y = win.y, width = win.width, height = win.height })
				if not inter then
					goto continue_redraw_under
				end

				call_userspace(
					id,
					win.redraw_handler,
					"handler",
					win.x + window_border_sizes.left + inter.x - 1,
					win.y + window_border_sizes.top + inter.y - 1,
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
	if true then
		return
	end
	local w = id_to_window(id)
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
	local w = id_to_window(id)
	if w.minimized then
		return
	end

	local index = id_to_visible_index(id)

	if index == 1 then
		return
	end

	local w_rect = { x = w.x, y = w.y, width = w.width, height = w.height }

	if not w.screen_buffer then
		for i = index - 1, 1, -1 do
			local win = id_to_window(visible[i])
			if win ~= nil then
				local inter =
					util.get_intersection(w_rect, { x = win.x, y = win.y, width = win.width, height = win.height })
				if inter ~= nil then
					redraw(id, inter.x, inter.y, inter.width, inter.height)
				end
			end
		end
		for i = index, 2, -1 do
			visible[i] = visible[i + 1]
		end
		visible[1] = id
		call_userspace(id, w.redraw_handler, "handler")
		return
	end

	w.geometry_lock:acquire()

	for i = index - 1, 1, -1 do
		local w_cur = id_to_window(visible[i])
		if w_cur ~= nil then
			local inter =
				util.get_intersection(w_rect, { x = w_cur.x, y = w_cur.y, width = w_cur.width, height = w_cur.height })
			if inter ~= nil then
				w_cur.geometry_lock:acquire()

				if w_cur.screen_buffer then
					gpu.bitblt(
						w_cur.screen_buffer,
						inter.x - w_cur.x + 1,
						inter.y - w_cur.y + 1,
						inter.width,
						inter.height,
						w.screen_buffer,
						inter.x - w.x + 1,
						inter.y - w.y + 1
					)
				else
					redraw(visible[i], inter.x, inter.y, inter.width, inter.height)
				end

				gpu.bitblt(
					w.screen_buffer,
					inter.x - w.x + 1,
					inter.y - w.y + 1,
					inter.width,
					inter.height,
					0,
					inter.x,
					inter.y
				)

				w_cur.geometry_lock:release()
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
	local w = id_to_window(id)
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
	if not id_to_window(id).minimized then
		return
	end
	id_to_window(id).minimized = false

	for i = 1, #visible do
		visible[i + 1] = visible[i]
	end
	visible[1] = id
end

---@param id integer
local function remove(id)
	local w = id_to_window(id)
	minimize(id)
	if last_window_id > id then
		last_window_id = id
	end

	if w.screen_buffer then
		gpu.freeBuffer(w.screen_buffer)
	end

	windows[id] = nil
end

---@param t thread
local function remove_all_of_thread(t)
	for i = 1, #windows do
		if id_to_window(i) ~= nil then
			if id_to_window(i).thread == t then
				remove(i)
			end
		end
	end
end

local function remove_all()
	for i = 1, #windows do
		if id_to_window(i) ~= nil then
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
	local w = id_to_window(id)
	if w.x == new_x and w.y == new_y and w.width == new_width and w.height == new_height then
		return
	end

	new_width = new_width < options.min_window_width and options.min_window_width or new_width
	new_height = new_height < options.min_window_height and options.min_window_height or new_height

	new_x = new_x + new_width - 1 > viewport_max_x and viewport_max_x - new_width + 1 or new_x
	new_x = new_x < 1 and 1 or new_x
	new_y = new_y + new_height - 1 > viewport_max_y - 2 and viewport_max_y - new_height - 1 or new_y
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
		do
			local old_viewport_in_new_coordinates = {
				x = new_x,
				y = new_y,
				width = w.viewport_width,
				height = w.viewport_height,
			}
			local rects = util.subtract(new_dimensions, old_viewport_in_new_coordinates)
			setColorsOfClient(w)
			for _, rect in pairs(rects) do
				gpu.fill(rect.x, rect.y, rect.width, rect.height, " ")
			end
		end

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
			if tmp_buffer then
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
			else --TODO:
			end
			gpu.freeBuffer(w.screen_buffer)
		else
			for _, rect in pairs(rects) do
				redraw(id, rect.x, rect.y, rect.width, rect.height)
			end
		end
		try_redraw(id, rects)
	end

	w.screen_buffer = tmp_buffer

	local top, bottom, left, right = get_window_border_sizes()

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
	local w = id_to_window(id)
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
	local w = id_to_window(id)
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

	local w = id_to_window(id)
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
						change_geometry(id, 1, 1, half_width, viewport_max_y - 2)
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
						change_geometry(id, half_width + 1, 1, half_width, viewport_max_y - 2)
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
		if mouse_event.action ~= "move" then
			draw_window(id)
		else
			draw_frame(id)
			draw_title(id)
		end
	else
		draw_frame(id)
		draw_title(id)
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
	local function call(id, func, ...)
		call_userspace(id, func, "internal", ...)
	end

	if options.debug then
		print_debug_info()
	end

	if mouse_event.window ~= nil and event ~= "scroll" and (event ~= "touch" or mouse_event.action == "tile") then
		call(mouse_event.window, mouse_event_handler, event, x, y)
		draw_memory()
		return
	end

	if y > viewport_max_y - 2 then
		taskbar.mouse_handler(event, x, y)
		draw_memory()
		return
	end

	-- Iterate over every window in order to see if the even clicked any of them
	for i = 1, #visible do
		local id = visible[i]
		local w = id_to_window(id)
		if x >= w.x and x < w.x + w.width and y >= w.y and y < w.y + w.height then
			local top, bottom, left, _ = get_window_border_sizes()

			call(id, move_to_top, id)

			if i ~= 1 then
				call(id, draw_window, id)
			end

			if y == w.y then -- clicked on top bar
				if event == "touch" then
					mouse_event.previous.x = x
					mouse_event.previous.y = y
					if x == w.x + w.width - 1 and not w.maximized then
						mouse_event.window = id
						mouse_event.action = "resize_top_right"
					elseif x == w.x + w.width - 2 then
						call(id, remove, id)
					elseif x == w.x + w.width - 3 then
						if w.maximized then
							call(id, unmaximize, id)
						else
							call(id, maximize, id)
						end
					elseif x == w.x + w.width - 4 then
						--call(id, minimize, i) TODO: The taskbar needs to be implemented
					elseif x == w.x + w.width - 5 then
						mouse_event.window = id
						mouse_event.action = "tile"
						show_tile_menu()
					elseif x == w.x and not w.maximized then
						mouse_event.window = id
						mouse_event.action = "resize_top_left"
					elseif not w.maximized then
						mouse_event.window = id
						mouse_event.action = "move"
					end
				end
			elseif x == w.x then -- click in left bar, but not in top bar
				if event == "touch" and y == w.y + w.height - 1 and not w.maximized then
					mouse_event.window = id
					mouse_event.action = "resize_bottom_left"
					mouse_event.previous.x = x
					mouse_event.previous.y = y
				end
			elseif x == w.x + w.width - 1 then -- click in right bar, but not in top bar
				if event == "touch" and y == w.y + w.height - 1 and not w.maximized then
					mouse_event.window = id
					mouse_event.action = "resize_bottom_right"
					mouse_event.previous.x = x
					mouse_event.previous.y = y
				end
			elseif x >= w.x + left and x <= w.x + w.width - left and y >= w.y + top and y < w.y + w.height - bottom then
				local user_x, user_y = x - w.x + left - 1, y - w.y + top - 1
				if event == "touch" and w.touch_handler then
					call_userspace(id, w.touch_handler, "handler", user_x, user_y, button)
				elseif event == "drag" and w.drag_handler then
					call_userspace(id, w.drag_handler, "handler", user_x, user_y, button)
				elseif event == "drop" and w.drop_handler then
					call_userspace(id, w.drop_handler, "handler", user_x, user_y, button)
				elseif event == "scroll" and w.scroll_handler then
					call_userspace(id, w.scroll_handler, "handler", user_x, user_y, scroll)
				end
			end
			draw_memory()
			return
		end
	end
	draw_memory()
end

local function start()
	gpu.freeAllBuffers()
	mouse_event = { window = nil, action = nil, buffer = nil, previous = { x = 0, y = 0 } }
	last_window_id = 1
	windows = {}
	visible = {}
end

return {
	start = start,
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
	get_toolbar_sizes = get_window_border_sizes,
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
	draw_memory = draw_memory,
}
