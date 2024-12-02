local vtk = require("VTK/core")

---@class Button
---@field new fun(b:Button, o): Button
local Button = vtk.new_clickable({
	text = "Button",
	pref_height = 3,

	min_width = 6,
	min_height = 3,

	background_color = 0xb0b0b0,
	background_color_edge = 0x6b6b6b,
	pressed_dark_factor = 0x303030,

	state = "released", ---@type "released"|"pressed"
})

function Button:pref_width()
	return self.text:len() + 5
end

function Button:touch_handler(x, y, _)
	if self.state == "pressed" then
		self.state = "released"
	end

	if x < self.width - 1 and y < self.height then
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

	_ENV.setBackground(self.parent_background)
	self.fill()

	if self.state == "released" then
		_ENV.setBackground(self.background_color_edge)
		self.fill(3, 2, self.width - 2, self.height - 1)

		_ENV.setBackground(self.background_color)
		self.fill(1, 1, self.width - 2, self.height - 1)

		self.set(
			math.floor((self.width - 2) / 2 - display_text:len() / 2) + 1,
			math.floor((self.height - 1) / 2),
			display_text
		)
	else
		_ENV.setBackground(self.background_color - self.pressed_dark_factor)
		self.fill(3, 2, self.width - 2, self.height - 1)

		self.set(
			math.floor((self.width - 2) / 2 - display_text:len() / 2) + 3,
			math.floor((self.height - 1) / 2) + 1,
			display_text
		)
	end
end

return {
	new_button = function(o) ---@return Button
		return Button:new(o)
	end,
}
