local fs = require("filesystem")
local gpu = require("component").gpu
local imager = require("imager")

local config = {
	logo_width = 14,
	logo_height = 7,
	background_high_depth = 0x7F7F7F,
	background_low_depth = 0x0000FF,
	foreground = 0xFFFFFF,
}

local default_logo = "/usr/lib/ventanos_data/ventanos_app.ppm"

local PATH = {
	"/usr/ventanos_apps",
	"/usr/lib/ventanos_apps",
	"/home/ventanos_apps",
	"/home/lib/ventanos_apps",
}

do
	local depth = gpu.getDepth()
	if depth == 8 then
		config.background = config.background_high_depth
	else
		config.background = config.background_low_depth
	end
	config.background_low_depth = nil
	config.background_high_depth = nil
end

local function get_app_name(app_directory)
	local file = fs.open(fs.concat(app_directory, "name"))
	local name = file:read(200) ---@type string
	file:close()
	if not name then
		return
	end
	return name:sub(1, name:len() - 1)
end

local programs = {} ---@type {name: string, logo_path: string, init_path: string}[]
local function seek_programs()
	local function add_programs_directories(path)
		for file in fs.list(path) do
			local cannonical_file = fs.concat(path, file)
			if fs.isDirectory(cannonical_file) then
				local has_init, has_logo, has_name = false, false, false
				for sub_file in fs.list(cannonical_file) do
					local segments = fs.segments(sub_file)
					if segments[#segments] == "init.lua" then
						has_init = true
					elseif segments[#segments] == "logo.ppm" then
						has_logo = true
					elseif segments[#segments] == "name" then
						has_name = true
					end
				end
				if has_init and has_name then
					local name = get_app_name(cannonical_file)
					local logo
					if has_logo then
						logo = fs.concat(cannonical_file, "logo.ppm")
					else
						logo = default_logo
					end
					if name == nil then
						break
					end
					programs[#programs + 1] = {
						name = name,
						logo_path = logo,
						init_path = fs.concat(cannonical_file, "init.lua"),
					}
				end
			end
		end
	end

	programs = {}
	for i = 1, #PATH do
		local path = PATH[i]
		if fs.exists(path) then
			if fs.isDirectory(path) then
				add_programs_directories(path)
			end
		end
	end
end

local left, top = 0, 0
local function renderer(handle)
	handle:setBackground(config.background)
	handle:setForeground(config.foreground)
	handle:fill(1, 1)

	local width, height = handle:getViewport()
	local end_x = math.floor((width - 1) / (config.logo_width + 1)) * (config.logo_width + 1)
	local end_y = math.floor((height - 1) / (config.logo_height + 2)) * (config.logo_height + 1)
	local offset_x = handle.window.x + left - 1
	local offset_y = handle.window.y + top - 1

	local app = 1
	for y = 1, end_y, config.logo_height + 1 do
		for x = 2, end_x, config.logo_width + 1 do
			if app > #programs then
				goto end_render
			end
			local name = programs[app].name:len() > config.logo_width
					and programs[app].name:sub(1, config.logo_width - 3) .. "..."
				or programs[app].name
			handle:set(7 - name:len() / 2 + x, y, name)
			app = app + 1
		end
	end

	::end_render::

	app = 1
	for y = 2 + offset_y, end_y + offset_y, config.logo_height + 1 do
		for x = 2 + offset_x, end_x + offset_x, config.logo_width + 1 do
			if app > #programs then
				return
			end
			imager.print_ppm(programs[app].logo_path, x, y, 1, 1, config.logo_width, config.logo_height)
			app = app + 1
		end
	end
end

local function get_app_selected(handle, x, y)
	local width, height = handle:getViewport()
	local app_width = config.logo_width + 1
	local app_height = config.logo_height + 1
	local n_wide = math.floor((width - 1) / app_width)
	local n_tall = math.floor((height - 1) / app_height)

	local col = nil
	for i = 1, n_wide do
		if x >= (i - 1) * app_width + 2 and x < i * app_width + 1 then
			col = i
			break
		end
	end

	if col == nil then
		return
	end

	for row = 1, n_tall do
		if y >= (row - 1) * app_height + 2 and y < row * app_height + 1 then
			return programs[(row - 1) * n_wide + col]
		end
	end
end

local selected_last_touch = nil
local function touch_handler(handle, x, y)
	selected_last_touch = get_app_selected(handle, x, y)
end

local function drop_handler(handle, x, y)
	local app = get_app_selected(handle, x, y)

	if app == nil or app ~= selected_last_touch then
		return
	end

	handle.window.touch_handler = nil
	handle.window.drop_handler = nil

	handle:fill(1, 1)

	local wm = require("ventanos_data/window_manager")

	wm.call_userspace(handle.id, function()
		handle:setTitle(app.name)

		for i, v in pairs(handle.window.environment) do
			_ENV[i] = v
		end

		loadfile(app.init_path)() -- This is where the magic happens: The entry point

		if Redraw == nil then
			error("When loading the application, function Redraw was not found in environment")
		end

		handle.window.redraw_handler = Redraw
		handle.window.touch_handler = Touch
		handle.window.drop_handler = Drop
		handle.window.drag_handler = Drag
		handle.window.scroll_handler = Scroll

		if Main then
			Main() -- This is it, the real deal, the actual entry point(if it has one anyway)
		end

		handle.window.redraw_handler()
	end, "main")
end
return function()
	local ventanos_api = require("ventanos")
	local wm = require("ventanos_data/window_manager")
	left, _, top = wm.get_toolbar_sizes()

	seek_programs()

	local env = {}
	local w = ventanos_api.new("Programs launcher", function()
		renderer(env.handle)
	end, function(x, y)
		touch_handler(env.handle, x, y)
	end, function(x, y)
		drop_handler(env.handle, x, y)
	end)
	env.handle = w

	wm.draw_window(w.id)
end
