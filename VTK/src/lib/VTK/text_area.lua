local vtk = require("VTK/core")

---@class TextArea
local TextArea = vtk.new_component()

function TextArea:init(text_area)
	text_area.foreground_color = 0xffffff
	text_area.background_color = 0x000000

	text_area.scroll_state = 1
	text_area.lines = {}
end

---@param string string
function TextArea:append_text(string)
	for line in string:gmatch("[^\n]+") do
		local start = line:find("\v")

		while start do
			table.insert(self.lines, line:sub(1, start - 1))
			line = line:sub(1, start - 1)
			local pad = ""
			for _ = 1, start do
				pad = pad .. " "
			end
			line = pad .. line
		end

		table.insert(self.lines, line)
	end
end

function TextArea:set_text(string)
	self.lines = {}
	self:append_text(string)
end

function TextArea:redraw_handler()
	self.setBackground(self.background_color)
	self.setForeground(self.foreground_color)

	self.fill()

	local offset_y = 0

	for i = self.scroll_state, self.height - offset_y - 1 do
		local message = self.lines[i]
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
				self.set(self.x + cursor_x - 1, self.y + offset_y + i - 1, to_print)
			end

			if cursor_x > self.width then
				cursor_x = 1
				offset_y = offset_y + 1
			end
		end
	end
end

function TextArea:scroll_handler(_, _, direction)
	self.scroll_state = self.scroll_state + direction
	self:redraw_handler()
end

return {
	new_text_area = function() ---@return TextArea
		return TextArea:new() ---@type TextArea
	end,
}
