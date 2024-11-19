local vtk_core = {}

---@class Component
---@field x integer -- Coordinates relative to the window not to the panel that may contain the object
---@field y integer
---@field width integer
---@field height integer
---@field pref_width nil|integer|fun():integer
---@field pref_height nil|integer|fun():integer
---@field min_width integer|fun():integer
---@field min_height integer|fun():integer
---@field max_width integer|fun():integer
---@field max_height integer|fun():integer
---@field redraw_handler fun()|nil
---@field touch_handler fun(x, y, button)|nil
---@field drop_handler fun(x, y, button)|nil
---@field drag_handler fun(x, y, button)|nil
---@field scroll_handler fun(x, y, direction)|nil
vtk_core.new_component = function()
	return {
		x = 1,
		y = 1,
		pref_width = 5,
		pref_height = 5,
		min_width = 0,
		min_height = 0,
		max_width = math.huge,
		max_height = math.huge,
	}
end

---@return boolean success
local function array_remove(array, value)
	for i = 1, #array do
		if array[i] == value then
			for j = i, #array do
				array[j] = array[j + 1]
			end
			return true
		end
	end
	return false
end

---@class ClickableComponent: Component
---@field add_press_listener fun(func:function)
---@field add_release_listener fun(func:function)
---@field remove_press_listener fun(func:function):boolean
---@field remove_release_listener fun(func:function):boolean
---@field press function
---@field release function
vtk_core.new_clickable_component = function()
	local clickable = vtk_core.new_component() ---@class ClickableComponent

	clickable.press_listeners, clickable.release_listeners = {}, {}

	clickable.add_press_listener = function(func)
		clickable.press_listeners[#clickable.press_listeners + 1] = func
	end

	clickable.remove_press_listener = function(func)
		return array_remove(clickable.press_listeners, func)
	end

	clickable.add_release_listener = function(func)
		clickable.release_listeners[#clickable.release_listeners + 1] = func
	end

	clickable.remove_release_listener = function(func)
		return array_remove(clickable.release_listeners, func)
	end

	clickable.press = function()
		for _, listener in pairs(clickable.press_listeners) do
			listener()
		end
	end

	clickable.release = function()
		for _, listener in pairs(clickable.release_listeners) do
			listener()
		end
	end

	return clickable
end

---@class Panel: Component
---@field private layout "box"
---@field private layout_orientation "vertical"|"horizontal"
---@field private components_array Component[]
---@field scrollable boolean
---@field set_layout fun(type: "box", orientation: "vertical"|"horizontal") -- https://docs.oracle.com/javase/tutorial/uiswing/layout/visual.html
---@field add_component fun(comp: Component)
---@field set_component fun(comp: Component, position: integer)
---@field remove_component fun(comp: Component): boolean
---@field components fun(): (fun(): Component)
vtk_core.new_panel = function()
	local panel = vtk_core.new_component() ---@class Panel

	panel.layout = "box"
	panel.layout_orientation = "horizontal"
	panel.scrollable = true
	panel.scroll_state = 0

	panel.components_array = {}
	panel.next_free = 0

	panel.set_layout = function(type, orientation)
		panel.layout = type
		panel.layout_orientation = orientation
	end

	panel.add_component = function(comp)
		panel.components_array[#panel.components_array + 1] = comp
	end

	panel.remove_component = function(comp)
		return array_remove(panel.components_array, comp)
	end

	panel.set_component = function(comp, position)
		panel.components_array[position] = comp
	end

	panel.components = function()
		local i = 0
		return function()
			i = i + 1
			return panel.components_array[i]
		end
	end

	local function get(component, field)
		local result
		if type(component[field]) == "function" then
			result = component[field]()
		else
			result = component[field]
		end
		if field:sub(1, 4) == "pref" and result == nil then
			result = get(component, "min_" .. field:sub(5))
		end

		return result
	end

	local function field_getter_constructor(field, horizontal_agregator, vertical_agregator)
		return function()
			local return_value = 0
			local agregator = panel.layout_orientation == "horizontal" and horizontal_agregator or vertical_agregator

			for comp in panel.components() do
				return_value = agregator(return_value, get(comp, field))
			end

			return return_value
		end
	end

	local function sum(a, b)
		return a + b
	end

	panel.pref_width = field_getter_constructor("pref_width", sum, math.max)
	panel.pref_height = field_getter_constructor("pref_height", math.max, sum)
	panel.min_width = field_getter_constructor("min_width", sum, math.max)
	panel.min_height = field_getter_constructor("min_height", math.max, sum)
	panel.max_width = field_getter_constructor("max_width", sum, math.max)
	panel.max_height = field_getter_constructor("max_height", math.max, sum)

	local function get_component_at_location(x, y)
		for comp in panel.components() do
			if x >= comp.x and x < comp.x + comp.width and y >= comp.y and y < comp.y + comp.height then
				return comp
			end
		end
	end

	-- We get the settings of each components in this convoluted way in order to call get() only once for each setting
	local function get_components_settings()
		local components_settings = {}
		local function fetch(settings, horizontal_agregator, vertical_agregator)
			local agregator = panel.layout_orientation == "horizontal" and horizontal_agregator or vertical_agregator
			for _, setting in pairs(settings) do
				local i, value = 0, 0

				components_settings[setting] = {}

				for comp in panel.components() do
					i = i + 1
					local field = get(comp, setting)
					components_settings[setting][i] = field
					value = agregator(value, field)
				end

				components_settings[setting].value = value
			end
		end
		fetch({ "pref_width", "min_width", "max_width" }, sum, math.max)
		fetch({ "pref_height", "min_height", "max_height" }, math.max, sum)
		return components_settings
	end

	local last_x, last_y, last_width, last_height, last_scroll
	--- Sets the x, y, width and height of all components if needed
	local function check_rearrange_without_scroll()
		if last_x == panel.x and last_y == panel.y and last_width == panel.width and last_height == panel.height then
			return
		end

		last_x, last_y, last_width, last_height = panel.x, panel.y, panel.width, panel.height

		-- The components at the start of the array have priority over the ones at the end
		local components_settings = get_components_settings()

		if panel.layout == "box" then
			local dim1, dim2, min1, max1, max2, coor1, coor2, space_asked

			if panel.layout_orientation == "horizontal" then
				dim1 = "width"
				dim2 = "height"
				coor1 = "x"
				coor2 = "y"
			else
				dim1 = "height"
				dim2 = "width"
				coor1 = "y"
				coor2 = "x"
			end

			max1, max2 = "max_" .. dim1, "max_" .. dim2
			min1 = "min_" .. dim1

			space_asked = panel[dim1]

			local i, pos = 0, panel[coor1]
			for component in panel.components() do
				i = i + 1
				local offset = math.ceil(math.min(panel[dim1], space_asked) / (#panel.components_array - i + 1))

				if components_settings[max1][i] < offset then
					component[dim1] = components_settings[max1][i]
				elseif components_settings[min1][i] > offset then
					component[dim1] = components_settings[min1][i]
				else
					component[dim1] = offset
				end
				space_asked = space_asked - component[dim1]

				component[dim2] = math.min(panel[dim2], components_settings[max2][i])

				component[coor1] = pos
				component[coor2] = panel[coor2]

				pos = pos + component[dim1]
			end
		else
			error("Unsuported layout:" .. panel.layout)
		end
	end

	local function check_rearrange_with_scroll()
		if
			last_x == panel.x
			and last_y == panel.y
			and last_width == panel.width
			and last_height == panel.height
			and last_scroll == panel.scroll_state
		then
			return
		end

		last_x, last_y, last_width, last_height, last_scroll =
			panel.x, panel.y, panel.width, panel.height, panel.scroll_state

		local components_settings = get_components_settings() -- A bit uneficient asking for all settings when we only need max and pref

		if panel.layout == "box" then
			local coor1, coor2, dim1, dim2, pref1, max2
			if panel.layout_orientation == "horizontal" then
				coor1 = "x"
				coor2 = "y"
				dim1 = "width"
				dim2 = "height"
			else
				coor1 = "y"
				coor2 = "x"
				dim1 = "height"
				dim2 = "width"
			end

			pref1 = "pref_" .. dim1
			max2 = "max_" .. dim2

			local offset, i = 0, 0
			for component in panel.components() do
				i = i + 1
				component[coor1] = panel[coor1] + offset
				component[coor2] = panel[coor2]
				component[dim1] = components_settings[pref1][i]
				component[dim2] = math.min(components_settings[max2][i], panel[dim2] - 1)
				offset = offset + component[dim1]
			end
		else
			error("Unsuported layout:" .. panel.layout)
		end
	end

	local function check_rearrange()
		if panel.scrollable then
			check_rearrange_with_scroll()
		else
			check_rearrange_without_scroll()
		end
	end

	local function handler_dispatcher(handler)
		return function(x, y, ...)
			check_rearrange()
			local comp = get_component_at_location(x, y)
			if comp == nil then
				return
			end

			if comp[handler] then
				comp[handler](x, y, ...)
			end
		end
	end

	panel.touch_handler = handler_dispatcher("touch_handler")
	panel.drop_handler = handler_dispatcher("drop_handler")
	panel.drag_handler = handler_dispatcher("drag_handler")

	local scroll_handler = handler_dispatcher("scroll_handler")
	panel.scroll_handler = function(x, y, direcction)
		if panel.scrollable then
			panel.scroll_state = panel.scroll_state + direcction
			panel.redraw_handler()
		else
			scroll_handler(x, y, direcction)
		end
	end

	panel.redraw_handler = function()
		check_rearrange()

		if panel.scrollable then
			for comp in panel.components() do
				if
					comp.width >= comp.min_width
					and comp.height >= comp.min_height
					and comp.x >= panel.x
					and comp.y >= panel.y
					and comp.x + comp.width <= panel.x + panel.width
					and comp.y + comp.height <= panel.y + panel.height
				then
					comp.redraw_handler()
				end
			end
		else
			local field = panel.layout_orientation == "horizontal" and "x" or "y"
			for comp in panel.components() do
				if
					comp.width >= comp.min_width
					and comp.height >= comp.min_height
					and comp[field] >= panel[field] + panel.scroll_state
					and comp.x + comp.width <= panel.x + panel.width
					and comp.y + comp.height <= panel.y + panel.height
				then
					comp.redraw_handler()
				end
			end
		end
	end

	return panel
end

return vtk_core
