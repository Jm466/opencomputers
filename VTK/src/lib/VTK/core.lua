---@class Component
local Component = {
	x = 1,
	y = 1,
	width = 0,
	height = 0,
	pref_width = 5,
	pref_height = 5,
	min_width = 0,
	min_height = 0,
	max_width = math.huge,
	max_height = math.huge,
}

function Component:new(prototype)
	return setmetatable(prototype and prototype or {}, { __index = self })
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

---@class ClickableComponent
---@field new fun(c:ClickableComponent, o): ClickableComponent
local Clickable = Component:new()

function Clickable:add_click_listener(func)
	if not self.click_listeners then
		self.click_listeners = {}
	end
	self.click_listeners[#self.click_listeners + 1] = func
end

function Clickable:remove_click_listener(func)
	return array_remove(self.click_listeners, func)
end

function Clickable:click()
	if self.click_listeners then
		for _, listener in pairs(self.click_listeners) do
			listener()
		end
	end
end

---@alias horizontal_field "max_width"|"pref_width"|"min_width"
---@alias vertical_field "max_height"|"pref_height"|"min_height"

local max = math.max
local min = math.min
local floor = math.floor
local function sum(a, b)
	return a + b
end

local function check_and_transfrom(x, y, width, height, comp_x, comp_y, comp_width, comp_height)
	x = x > 0 and x or 1
	x = x <= comp_width and x or comp_width
	y = y > 0 and y or 1
	y = y <= comp_height and y or comp_height
	width = width >= 0 and width or 0
	width = x + width - 1 <= comp_width and width or comp_width - x + 1
	height = height >= 0 and height or 0
	height = y + height - 1 <= comp_height and height or comp_height - y + 1

	-- Now coordinates and dimensions are inside the component

	return comp_x + x - 1, comp_y + y - 1, width, height
end

local function sandboxed_set(panel, component, x, y, value, vertical)
	local width, height
	x, y, width, height = check_and_transfrom(
		x,
		y,
		vertical and value:len() or 1,
		vertical and 1 or value:len(),
		component.x,
		component.y,
		component.width,
		component.height
	)

	if vertical then
		if y < 1 then
			value = value:sub(-y + 2)
			y = 1
			height = height + y - 1
		end
		if y + height - 1 > panel.height then
			value = value:sub(1, panel.height - y + 1)
		end
	else
		if x < 1 then
			value = value:sub(-x + 2)
			x = 1
			width = width + x - 1
		end
		if x + width - 1 > panel.width then
			value = value:sub(1, panel.width - x + 1)
		end
	end

	if width ~= 0 and height ~= 0 then
		panel.set(x, y, value, vertical)
	end
end

local function sandboxed_fill(panel, component, x, y, width, height, char)
	x = x and x or 1
	y = y and y or 1
	width = width and width or component.width
	height = height and height or component.height
	x, y, width, height =
		check_and_transfrom(x, y, width, height, component.x, component.y, component.width, component.height)

	if x < 1 then
		width = width + x - 1
		x = 1
	end
	if y < 1 then
		height = height + y - 1
		y = 1
	end
	if x + width - 1 > panel.width then
		width = panel.width - x + 1
	end
	if y + height - 1 > panel.height then
		height = panel.height - y + 1
	end

	if width ~= 0 and height ~= 0 then
		panel.fill(x, y, width, height, char)
	end
end

local function sandboxed_copy(panel, component, x, y, width, height, tx, ty)
	local meta_x, meta_y, meta_width, meta_height
	local initial_meta_x, initial_meta_y, initial_meta_width, initial_meta_height =
		min(x, x + tx), min(y, y + ty), max(width, width + tx), max(height, height + ty)

	meta_x, meta_y, meta_width, meta_height = check_and_transfrom(
		initial_meta_x,
		initial_meta_y,
		initial_meta_width,
		initial_meta_height,
		component.x,
		component.y,
		component.width,
		component.height
	)

	if meta_x < 1 then
		meta_width = meta_width + meta_x - 1
		meta_x = 1
	end
	if meta_y < 1 then
		meta_height = meta_height + meta_y - 1
		meta_y = 1
	end
	if meta_x + meta_width - 1 > panel.width then
		meta_width = panel.width - meta_x + 1
	end
	if meta_y + meta_height - 1 > panel.height then
		meta_height = panel.height - meta_y + 1
	end

	x = x + meta_x - initial_meta_x
	y = y + meta_y - initial_meta_y
	width = width + meta_width - initial_meta_width
	height = height + meta_height - initial_meta_height

	if width ~= 0 and height ~= 0 then
		panel.copy(x, y, width, height, tx, ty)
	end
end

---@param panel Panel
---@param component Component
local function sandbox(panel, component)
	component.set = function(...)
		sandboxed_set(panel, component, ...)
	end

	component.fill = function(...)
		sandboxed_fill(panel, component, ...)
	end

	component.copy = function(...)
		sandboxed_copy(panel, component, ...)
	end
end

---@param component Component
---@param field horizontal_field|vertical_field
---@return horizontal_field|vertical_field
local function get(component, field)
	local result
	if type(component[field]) == "function" then
		result = component[field](component)
	else
		result = component[field]
	end
	if field:sub(1, 4) == "pref" and result == nil then
		result = get(component, "min_" .. field:sub(5))
	end

	if result == nil then
		error()
	end

	return result
end

---@class Panel
---@field new fun(p:Panel, o): Panel
local Panel = Component:new({
	layout = "box",
	layout_orientation = "horizontal",
	scrollable = false,
	scroll_state = 0,
	length_sum = 0,
	scroll_max = 0,

	scroll_bar_color = 0x457AA2,
	scroll_bar_button_color = 0xffffff,
	scroll_bar_background_dark_factor = 0x1e1e1e,

	next_free = 0,
})

function Panel:add_component(comp)
	if not self.components_array then
		self.components_array = {}
	end
	self.components_array[#self.components_array + 1] = comp
	sandbox(self, comp)
	self.context_changed = true
end

function Panel:remove_component(comp)
	self.context_changed = true
	return array_remove(self.components_array, comp)
end

function Panel:set_component(comp, position)
	self.context_changed = true
	self.components_array[position] = comp
end

function Panel:components()
	local i = 0
	---@return Component
	return function()
		i = i + 1
		return self.components_array[i]
	end
end

---@param horizontal table<horizontal_field, nil>
---@param vertical table<vertical_field, nil>
---@alias T table<integer|"value", integer>
---@return {max_width: T, max_height: T, pref_width: T, pref_height: T, min_width: T, min_height: T}
function Panel:get_components_settings(horizontal, vertical)
	local components_settings = {}
	local function fetch(settings, horizontal_agregator, vertical_agregator)
		local agregator = self.layout_orientation == "horizontal" and horizontal_agregator or vertical_agregator
		for _, setting in pairs(settings) do
			local i, value = 0, 0

			components_settings[setting] = {}

			for comp in self:components() do
				i = i + 1
				local field = get(comp, setting)
				components_settings[setting][i] = field
				value = agregator(value, field)
			end

			components_settings[setting].value = value
		end
	end
	fetch(horizontal, sum, math.max)
	fetch(vertical, math.max, sum)
	return components_settings
end

---@param x integer
---@param y integer
---@return Component|nil
function Panel:get_component_at_location(x, y)
	for comp in self:components() do
		if x >= comp.x and x < comp.x + comp.width and y >= comp.y and y < comp.y + comp.height then
			return comp
		end
	end
end

--- Sets the x, y, width and height of all components if needed
function Panel:calculate_geometry()
	if not self:needs_rearrange() then
		return
	end

	if self.layout ~= "box" then
		error("Unsuported layout:" .. self.layout)
	end

	local background = self.background_color and self.background_color or self.parent_background

	if self.scrollable then
		local i, offset = 0, -self.scroll_state

		if self.layout_orientation == "horizontal" then
			local components_settings = self:get_components_settings({ "pref_width" }, { "max_height" })
			for component in self:components() do
				i = i + 1
				component.x = self.x + offset
				component.y = self.y
				component.width = components_settings.pref_width[i]
				component.height = math.min(components_settings.max_height[i], self.height - 1)
				component.parent_background = background
				offset = offset + component.width
			end
			self.length_sum = components_settings.pref_width.value
			self.scroll_max = self.length_sum - self.width
		else
			local components_settings = self:get_components_settings({ "max_width" }, { "pref_height" })
			for component in self:components() do
				i = i + 1
				component.x = self.x
				component.y = self.y + offset
				component.width = math.min(components_settings.max_width[i], self.width - 1)
				component.height = components_settings.pref_height[i]
				component.parent_background = background
				offset = offset + component.height
			end
			self.length_sum = components_settings.pref_height.value
			self.scroll_max = self.length_sum - self.height
		end
	else -- Without scroll
		local i = 0

		if self.layout_orientation == "horizontal" then
			local components_settings = self:get_components_settings({ "max_width", "min_width" }, { "max_height" })
			local pos = 1
			local space_asked = self.width

			for component in self:components() do
				i = i + 1
				local offset = math.ceil(math.min(self.width, space_asked) / (#self.components_array - i + 1))

				if components_settings.max_width[i] < offset then
					component.width = components_settings.max_width[i]
				elseif components_settings.min_width[i] > offset then
					component.width = components_settings.min_width[i]
				else
					component.width = offset
				end
				space_asked = space_asked - component.width

				component.height = math.min(self.height, components_settings.max_height[i])

				component.x = pos
				component.y = 1

				component.parent_background = background

				pos = pos + component.width
			end
		else
			local components_settings = self:get_components_settings({ "max_width" }, { "max_height", "min_height" })
			local pos = 1
			local space_asked = self.height

			for component in self:components() do
				i = i + 1
				local offset = math.ceil(math.min(self.height, space_asked) / (#self.components_array - i + 1))

				if components_settings.max_height[i] < offset then
					component.height = components_settings.max_height[i]
				elseif components_settings.min_height[i] > offset then
					component.height = components_settings.min_height[i]
				else
					component.height = offset
				end
				space_asked = space_asked - component.height

				component.width = math.min(self.width, components_settings.max_width[i])

				component.y = pos
				component.x = 1

				component.parent_background = background

				pos = pos + component.height
			end
		end
	end
end

function Panel:needs_rearrange()
	if
		self.last_x == self.x
		and self.last_y == self.y
		and self.last_width == self.width
		and self.last_height == self.height
		and self.last_scrollable == self.scrollable
		and self.last_scroll == self.scroll_state
		and self.last_layout == self.layout
		and self.last_orientation == self.layout_orientation
		and not self.context_changed
	then
		return false
	end

	self.last_x, self.last_y, self.last_width, self.last_height, self.last_scroll, self.last_scrollable, self.last_layout, self.last_orientation =
		self.x,
		self.y,
		self.width,
		self.height,
		self.scroll_state,
		self.scrollable,
		self.layout,
		self.layout_orientation

	self.context_changed = false

	return true
end

function Panel:draw_scrollbar()
	if self.layout ~= "box" then
		error("Scrollbar only supported for box layout")
	end

	local background = self.background_color and self.background_color or self.parent_background
	local x, y, bar, link, length

	if self.layout_orientation == "horizontal" then
		_ENV.setBackground(background - self.scroll_bar_background_dark_factor)
		self.fill(1, self.height, self.width, 1)

		x = math.ceil(self.scroll_state * self.width / self.length_sum) + 1
		y = self.height
		length = min(self.width, floor((self.width ^ 2) / self.length_sum)) - 2
		link = "-"
	else
		_ENV.setBackground(background - self.scroll_bar_background_dark_factor)
		self.fill(self.width, 1, 1, self.height)

		x = self.width
		y = math.ceil(self.scroll_state * self.height / self.length_sum) + 1
		length = min(self.height, floor((self.height ^ 2) / self.length_sum)) - 2
		link = "|"
	end

	bar = "O"
	for _ = 1, length do
		bar = bar .. link
	end
	bar = bar .. "O"

	_ENV.setForeground(self.scroll_bar_button_color)
	_ENV.setBackground(self.scroll_bar_color)
	self.set(x, y, bar, self.layout_orientation == "vertical")
end

function Panel:partial_redraw_with_scrollbar(scroll_direcction)
	_ENV.setBackground(self.background_color and self.background_color or self.parent_background)
	if self.layout_orientation == "horizontal" then
		if scroll_direcction == 1 then
			self.copy(1, 1, self.width - 1, self.height - 1, 1, 0)
			self.fill(1, 1, 1, self.height - 1)
		else
			self.copy(2, 1, self.width - 1, self.height - 1, -1, 0)
			self.fill(1, self.width, 1, self.height - 1)
		end
	else
		if scroll_direcction == 1 then
			self.copy(1, 1, self.width - 1, self.height - 1, 0, 1)
			self.fill(1, 1, self.width - 1, 1)
		else
			self.copy(1, 2, self.width - 1, self.height - 1, 0, -1)
			self.fill(self.height, 1, self.width - 1, 1)
		end
	end

	self:calculate_geometry()

	self:draw_scrollbar()

	for comp in self:components() do
		if
			comp.width >= get(comp, "min_width")
			and comp.height >= get(comp, "min_height")
			and comp.x + comp.width > 1
			and comp.y + comp.height > 1
			and comp.x < self.x + self.width
			and comp.y < self.y + self.height
			and comp.redraw_handler
		then -- Redraw capable
			if self.layout_orientation == "horizontal" then
				if
					comp.x - scroll_direcction < self.x
					or comp.x + comp.width - scroll_direcction > self.x + self.width
				then
					comp:redraw_handler()
				end
			else
				if
					comp.y - scroll_direcction < self.y
					or comp.y + comp.height - scroll_direcction > self.y + self.height
				then
					comp:redraw_handler()
				end
			end
		end
	end
end

function Panel.field_getter_constructor(field, horizontal_agregator, vertical_agregator)
	return function(self)
		local return_value = 0
		local agregator = self.layout_orientation == "horizontal" and horizontal_agregator or vertical_agregator

		for comp in self:components() do
			return_value = agregator(return_value, get(comp, field))
		end

		return return_value
	end
end

Panel.pref_width = Panel.field_getter_constructor("pref_width", sum, max)
Panel.pref_height = Panel.field_getter_constructor("pref_height", max, sum)
Panel.min_width = Panel.field_getter_constructor("min_width", sum, max)
Panel.min_height = Panel.field_getter_constructor("min_height", max, sum)
Panel.max_width = Panel.field_getter_constructor("max_width", sum, max)
Panel.max_height = Panel.field_getter_constructor("max_height", max, sum)

---@param handler "touch_handler"|"drop_handler"|"drag_handler"|"scroll_handler"
function Panel:meta_handler(handler, x, y, ...)
	self:calculate_geometry()
	local comp = self:get_component_at_location(x, y)
	if comp and comp[handler] then
		comp[handler](comp, x - comp.x + 1, y - comp.y + 1, ...)
	end
end

---@return boolean clickhandled If false, meta_handler needs to be called
function Panel:scrollbar_click_handler(x, y)
	if self.layout == "box" then
		if self.layout_orientation == "horizontal" then
			if y < self.height then
				return false
			end
			self.scroll_state = x * self.length_sum / self.width
			self.scroll_state = self.scroll_state - min(self.width, floor((self.width ^ 2) / self.length_sum)) + 2
		else
			if x < self.width then
				return false
			end
			self.scroll_state = y * self.length_sum / self.height
			self.scroll_state = self.scroll_state - min(self.height, floor((self.height ^ 2) / self.length_sum)) + 2
		end
		self.context_changed = true
		self.scroll_state = max(0, min(self.scroll_max, floor(self.scroll_state)))
		self:redraw_handler()
	end
	return true
end

function Panel:touch_handler(x, y)
	if self.scrollable and self:scrollbar_click_handler(x, y) then
		return
	end
	self:meta_handler("touch_handler", x, y)
end

function Panel:drop_handler(x, y)
	self:meta_handler("drop_handler", x, y)
end

function Panel:drag_handler(x, y)
	self:meta_handler("drag_handler", x, y)
end

function Panel:scroll_handler(x, y, direcction)
	if self.scrollable then
		local last_state = self.scroll_state
		self.scroll_state = self.scroll_state - direcction
		self.scroll_state = self.scroll_state > 0 and self.scroll_state or 0
		self.scroll_state = self.scroll_state < self.scroll_max and self.scroll_state or self.scroll_max
		if last_state ~= self.scroll_state then
			self:partial_redraw_with_scrollbar(direcction)
		end
	else
		self:meta_handler("scroll_handler", x, y, direcction)
	end
end

function Panel:redraw_handler()
	local background = self.background_color and self.background_color or self.parent_background
	_ENV.setBackground(background)
	self.fill(self.x, self.y, self.width, self.height)

	self:calculate_geometry()

	if self.scrollable then
		self:draw_scrollbar()
	end

	for comp in self:components() do
		if
			comp.width >= get(comp, "min_width")
			and comp.height >= get(comp, "min_height")
			and comp.x + comp.width > 1
			and comp.y + comp.height > 1
			and comp.x < self.x + self.width
			and comp.y < self.y + self.height
			and comp.redraw_handler
		then
			comp:redraw_handler()
		end
	end
end

return {
	new_component = function(o) ---@return Component
		return Component:new(o)
	end,
	new_clickable = function(o) ---@return ClickableComponent
		return Clickable:new(o)
	end,
	new_panel = function(o) ---@return Panel
		return Panel:new(o)
	end,
}
