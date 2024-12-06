local vtk = require("VTK/core")

---@class Button
local Button = vtk.new_clickable()

function Button:init(button)
	button.text = "Button"
	button.pref_height = 3
	button.min_width = 6
	button.min_height = 1
	button.background_color = 0xb0b0b0
	button.background_color_edge = 0x6b6b6b
	button.pressed_dark_factor = 0x303030
	button.state = "released" ---@type "released"|"pressed"
end

function Button:pref_width()
	return self.text:len() + 5
end

function Button:touch_handler(x, y, _)
	if self.state == "pressed" then
		self.state = "released"
	end

	if y == 1 or x < self.width - 1 and y < self.height then
		self.state = "pressed"
		self:redraw_handler()
	end
end

function Button:drop_handler()
	if self.state == "pressed" then
		self.state = "released"
		self:redraw_handler()
		self:click()
	end
end

function Button:redraw_handler()
	local display_text = self.text:len() <= self.width - 1 and self.text or self.text:sub(1, self.width - 2)

	if self.height > 1 then
		_ENV.setBackground(self.background_color_edge)
		self.fill()
	end

	if self.state == "released" then
		_ENV.setBackground(self.background_color)
		if self.height > 1 then
			self.fill(1, 1, self.width - 2, self.height - 1)
		else
			self.fill()
		end

		self.set(
			math.ceil((self.width - 2) / 2 - display_text:len() / 2) + 1,
			math.ceil((self.height - 1) / 2),
			display_text
		)
	else
		_ENV.setBackground(self.background_color - self.pressed_dark_factor)
		if self.height > 1 then
			self.fill(3, 2, self.width - 2, self.height - 1)
		else
			self.fill()
		end

		self.set(
			math.ceil((self.width - 2) / 2 - display_text:len() / 2) + (self.height == 1 and 1 or 3),
			math.ceil((self.height - 1) / 2) + 1,
			display_text
		)
	end
end

return {
	new_button = function() ---@return Button
		return Button:new() ---@type Button
	end,
}
