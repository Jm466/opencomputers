local vtk = require("VTK_core")

local vtk_button = {}

---@class Button: ClickableComponent
---@field text string
---@field background_color_bottom integer
---@field background_color_middle integer
---@field pressed_factor integer
---@field add_press_listener fun(func:function)
---@field add_release_listener fun(func:function)
vtk_button.new_button = function()
	local button = vtk.new_clickable_component() ---@class Button

	button.preferred_height = 3
	button.min_height = 2
	button.min_width = 5

	button.background_color_top = 0xe6e6e6 -- Unused
	button.background_color_bottom = 0x6b6b6b
	button.background_color_middle = 0xb0b0b0
	button.pressed_dark_factor = 0x303030

	button.state = "released" ---@type "released"|"pressed"

	button.redraw_handler = function()
		local display_text = button.text:len() <= button.width - 1 and button.text
			or button.text:sub(1, button.width - 4) .. "..."

		_ENV.setBackground(button.background_color_bottom)
		_ENV.fill(button.x, button.y, button.width, button.height)

		_ENV.setBackground(button.background_color_top)
		_ENV.fill(button.x, button.y, button.width - 1, button.height - 1)

		_ENV.set(
			button.x + math.floor((button.width - 1) - (display_text:len() / 2)),
			button.y + math.floor((button.height - 1) / 2),
			button.width - 2,
			button.height - 2
		)
	end

	button.touch_handler = function(x, y, _)
		if x >= button.x and x < button.x + button.width - 1 and y >= button.y and y < button.y + button.height - 1 then
			button.press()
		end
	end

	button.drop_handler_handler = function(x, y, _)
		if x >= button.x and x < button.x + button.width - 1 and y >= button.y and y < button.y + button.height - 1 then
			button.release()
		end
	end

	return button
end

---@param button Button
---@param text string
vtk_button.set_text = function(button, text)
	button.text = text
	button.preferred_width = text:len() + 4
end

return vtk_button
