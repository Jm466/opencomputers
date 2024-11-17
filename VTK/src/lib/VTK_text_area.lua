local vtk = require("VTK_core")

local vtk_text_area = {}

---@class TextArea: Component
---@field set_text fun(string)
---@field append_text fun(string)
---@field foreground_color integer
---@field background_color integer
vtk_text_area.new_text_area = function()
	local text_area = vtk.new_component() ---@class TextArea

	text_area.foreground_color = 0xffffff
	text_area.background_color = 0x000000

	text_area.scroll_state = 1
	text_area.lines = {}

	text_area.append_text = function(string) ---@param string string
		for line in string:gmatch("[^\n]+") do
			local start = line:find("\v")

			while start do
				table.insert(text_area.lines, line:sub(1, start - 1))
				line = line:sub(1, start - 1)
				local pad = ""
				for _ = 1, start do
					pad = pad .. " "
				end
				line = pad .. line
			end

			table.insert(text_area.lines, line)
		end
	end

	text_area.set_text = function(string)
		text_area.lines = {}
		text_area.append_text(string)
	end

	text_area.redraw_handler = function()
		_ENV.setBackground(text_area.background_color)
		_ENV.setForeground(text_area.foreground_color)

		_ENV.fill(text_area.x, text_area.y, text_area.width, text_area.height)

		local offset_y = 0

		for i = text_area.scroll_state, text_area.height - offset_y - 1 do
			local message = text_area.lines[i]
			local cursor_x = 1

			while message:len() > 0 do
				local to_print = message:sub(1, 1)
				message = message:sub(2)

				if to_print == "\t" then
					cursor_x = ((cursor_x - 1) - ((cursor_x - 1) % 8)) + 9
				elseif to_print == "\r" then
					cursor_x = 1
				elseif to_print == "\b" then
					cursor_x = cursor_x - 1
				else
					_ENV.set(text_area.x + cursor_x - 1, text_area.y + offset_y + i - 1, to_print)
				end

				if cursor_x > text_area.width then
					cursor_x = 1
					offset_y = offset_y + 1
				end
			end
		end
	end

	text_area.scroll_handler = function(_, _, direction)
		text_area.scroll_state = text_area.scroll_state + direction
		text_area.redraw_handler()
	end

	return text_area
end

return vtk_text_area
