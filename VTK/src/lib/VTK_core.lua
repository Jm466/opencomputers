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
---@field set_layout fun(type: "box", orientation: "vertical"|"horizontal") -- https://docs.oracle.com/javase/tutorial/uiswing/layout/visual.html
---@field add_component fun(comp: Component)
---@field set_component fun(comp: Component, position: integer)
---@field remove_component fun(comp: Component): boolean
---@field components fun(): (fun(): Component)
vtk_core.new_panel = function()
	local panel = vtk_core.new_component() ---@class Panel

	panel.layout = "box"
	panel.layout_orientation = "horizontal"

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

	local last_x, last_y, last_width, last_height
	--- Sets the x, y, width and height of all components if needed
	local function check_rearrange()
		if last_x == panel.x and last_y == panel.y and last_width == panel.width and last_height == panel.height then
			return
		end

		-- The components at the start of the array have priority over the ones at the end

		-- We get the settings of each components in this convoluted way in order to call get() only once for each setting
		local components_settings = {}
		local function get_component_settings(settings, horizontal_agregator, vertical_agregator)
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

		get_component_settings({ "pref_width", "min_width", "max_width" }, sum, math.max)
		get_component_settings({ "pref_height", "min_height", "max_height" }, math.max, sum)

		if panel.layout == "box" then
			local setting, setting2, min, max, max2, coor1, coor2, space_asked

			if panel.layout_orientation == "horizontal" then
				setting = "width"
				setting2 = "height"
				coor1 = "x"
				coor2 = "y"
			else
				setting = "height"
				setting2 = "width"
				coor1 = "y"
				coor2 = "x"
			end

			max, max2 = "max_" .. setting, "max_" .. setting2
			min = "min_" .. setting

			space_asked = panel[setting]

			local i, pos = 0, panel[coor1]
			for component in panel.components() do
				i = i + 1
				local offset = math.ceil(math.min(panel[setting], space_asked) / (#panel.components_array - i + 1))

				if components_settings[max][i] < offset then
					component[setting] = components_settings[max][i]
				elseif components_settings[min][i] > offset then
					component[setting] = components_settings[min][i]
				else
					component[setting] = offset
				end
				space_asked = space_asked - component[setting]

				component[setting2] = math.min(panel[setting2], components_settings[max2][i])

				component[coor1] = pos
				component[coor2] = panel[coor2]

				pos = pos + component[setting]
			end
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
	panel.scroll_handler = handler_dispatcher("scroll_handler")

	panel.redraw_handler = function()
		check_rearrange()

		for comp in panel.components() do
			if
				comp.width >= comp.min_width
				and comp.height >= comp.min_height
				and comp.x + comp.width <= panel.x + panel.width
				and comp.y + comp.height <= panel.y + panel.height
			then
				comp.redraw_handler()
			end
		end
	end

	return panel
end

return vtk_core
