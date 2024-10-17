local fs = require("filesystem")
local gpu = require("component").gpu
local imager = require("imager")
local thread = require("thread")

local config = {
	logo_width = 14,
	logo_height = 7,
	background_high_depth = 0x7F7F7F,
	background_low_depth = 0x0000FF,
	foreground = 0xFFFFFF,
}

local PATH = {
	"/home/lib/ventanos_apps",
	"/usr/lib/ventanos_apps",
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
					if has_logo and has_init and has_name then
						local name = get_app_name(cannonical_file)
						if name == nil then
							break
						end
						programs[#programs + 1] = {
							name = name,
							logo_path = fs.concat(cannonical_file, "logo.ppm"),
							init_path = fs.concat("ventanos_apps", file),
						}
						break
					end
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
---@param handler WindowHandler
local function renderer(handler)
	handler:setBackground(config.background)
	handler:setForeground(config.foreground)
	handler:fill(1, 1)

	local width, height = handler:getViewport()
	local end_x = math.floor((width - 1) / (config.logo_width + 1)) * (config.logo_width + 1)
	local end_y = math.floor((height - 1) / (config.logo_height + 2)) * (config.logo_height + 1)
	local offset_x = handler.window.x + left - 1
	local offset_y = handler.window.y + top - 1

	local app = 1
	for x = 2, end_x, config.logo_width + 1 do
		for y = 1, end_y, config.logo_height + 1 do
			if app > #programs then
				goto end_render
			end
			local name = programs[app].name:len() > config.logo_width
					and programs[app].name:sub(1, config.logo_width - 3) .. "..."
				or programs[app].name
			handler:set(7 - name:len() / 2 + 1, y, name)
			app = app + 1
		end
	end

	::end_render::

	app = 1
	for x = 2 + offset_x, end_x + offset_x, config.logo_width + 1 do
		for y = 2 + offset_y, end_y + offset_y, config.logo_height + 2 do
			if app > #programs then
				return
			end
			imager.print_ppm(programs[app].logo_path, x, y, 1, 1, config.logo_width, config.logo_height)
			app = app + 1
		end
	end
end

local function get_app_selected(handler, x, y)
	local width, height = handler:getViewport()
	local app_width = config.logo_width + 1
	local app_height = config.logo_height + 1
	local n_wide = math.floor((width - 1) / app_width)
	local n_tall = math.floor((height - 1) / app_height)

	local col = nil
	for i = 1, n_wide * app_width, app_width do
		if x >= (i - 1) * app_width + 2 and x < i * app_width + 2 then
			col = i
			break
		end
	end

	if col == nil then
		return
	end

	for i = 1, n_tall * app_height, app_height do
		if y >= (i - 1) * app_height + 2 and y < i * app_height + 2 then
			return programs[(col - 1) * n_wide + i]
		end
	end
end

local selected_last_touch = nil
local function touch_handler(handler, x, y)
	selected_last_touch = get_app_selected(handler, x, y)
end

local function drop_handler(handler, x, y)
	local app = get_app_selected(handler, x, y)

	if app == nil or app ~= selected_last_touch then
		return
	end

	handler.window.touch_handler = nil
	handler.window.drop_handler = nil

	handler:fill(1, 1)

	local wm = require("ventanos_data/window_manager")

	wm.call_userspace(handler.id, function()
		handler:setTitle(app.name)

		local main_table = require(app.init_path) -- This is where the magic happens: The entry point

		if main_table == nil then
			error("When loading the application, init.lua did not return a table")
		elseif main_table.redraw_handler == nil then
			error("When loading the application, redraw_handler was not found in main_table")
		end

		handler.window.redraw_handler = main_table.redraw_handler
		if main_table.touch_handler then
			handler.window.touch_handler = main_table.touch_handler
		end
		if main_table.drop_handler then
			handler.window.drop_handler = main_table.drop_handler
		end
		if main_table.drag_handler then
			handler.window.drag_handler = main_table.drag_handler
		end
		if main_table.scroll_handler then
			handler.window.scroll_handler = main_table.scroll_handler
		end

		if main_table.main then
			main_table.main() -- This is it, the real deal, the actual entry point, if it has one anyway
		end

		main_table.redraw_handler(handler)
	end, "main")
end

return function()
	local ventanos_api = require("ventanos")
	local wm = require("ventanos_data/window_manager")
	left, _, top = wm.get_toolbar_sizes()

	seek_programs()

	local w = ventanos_api.new("Programs launcher", renderer, touch_handler, drop_handler)
	wm.draw_window(w.id)
end
