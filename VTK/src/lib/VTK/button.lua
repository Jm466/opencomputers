local vtk = require("VTK/core")

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

	button.pref_width = function()
		return button.text:len() + 5
	end
	button.pref_height = 2

	button.max_width = button.pref_width
	button.max_height = 2

	button.min_width = 6
	button.min_height = 2

	button.background_color_top = 0xe6e6e6 -- Unused
	button.background_color_bottom = 0x6b6b6b
	button.background_color_middle = 0xb0b0b0
	button.pressed_dark_factor = 0x303030

	button.state = "released" ---@type "released"|"pressed"

	button.redraw_handler = function()
		local display_text = button.text:len() <= button.width - 1 and button.text
			or button.text:sub(1, button.width - 4) .. "..."

		if button.state == "released" then
			_ENV.setBackground(button.background_color_bottom)
			_ENV.fill(button.x, button.y, button.width, button.height)

			_ENV.setBackground(button.background_color_middle)
			_ENV.fill(button.x, button.y, button.width - 2, button.height - 1)

			_ENV.set(
				button.x + math.floor((button.width - 2) / 2 - display_text:len() / 2) + 1,
				button.y + math.floor((button.height - 1) / 2),
				display_text
			)
		else
			_ENV.setBackground(button.background_color_middle)
			_ENV.fill(button.x, button.y, button.width, button.height)

			_ENV.setBackground(button.background_color_middle - button.pressed_dark_factor)
			_ENV.fill(button.x + 2, button.y + 1, button.width - 2, button.height - 1)

			_ENV.set(
				button.x + math.floor((button.width - 2) / 2 - display_text:len() / 2) + 3,
				button.y + math.floor((button.height - 1) / 2) + 1,
				display_text
			)
		end
	end

	button.touch_handler = function(x, y, _)
		if x >= button.x and x < button.x + button.width - 1 and y >= button.y and y < button.y + button.height - 1 then
			button.state = "pressed"
			button.redraw_handler()
			button.press()
		end
	end

	button.drop_handler = function(x, y, _)
		if x >= button.x and x < button.x + button.width - 1 and y >= button.y and y < button.y + button.height - 1 then
			button.state = "released"
			button.redraw_handler()
			button.release()
		end
	end

	return button
end

return vtk_button
