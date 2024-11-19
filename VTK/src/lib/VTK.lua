local ventanos = require("ventanos")
local core = require("VTK_core")

local vtk = {}

---@class Frame: Panel
---@field background_color integer
---@field foreground_color integer
local function new_frame()
	local frame = core.new_panel()

	frame.background_color = 0x79797

	local true_redraw = frame.redraw_handler
	frame.redraw_handler = function()
		_ENV.setBackground(frame.background_color)
		_ENV.fill()

		true_redraw()
	end

	return frame
end

--- Creates a frame for the window. Cannot be called more than once and must be called outside of the main function
---@return Frame
vtk.init = function()
	for _, func in pairs({ "Redraw", "Touch", "Drop", "Drag", "Scroll" }) do
		if _ENV.func then
			error("Function " .. func .. "() already defined by user")
		end
	end

	local frame = new_frame()

	_ENV.Redraw = frame.redraw_handler
	_ENV.Touch = frame.touch_handler
	_ENV.Drop = frame.drop_handler
	_ENV.Drag = frame.drag_handler
	_ENV.Scroll = frame.scroll_handler

	return frame
end

--- Creates a new window and returns the frame of the window and the window. Can be called anytime
---@param title string Title of the window
---@return Frame
---@return WindowHandle
vtk.new_window = function(title)
	local frame = new_frame()

	return frame,
		ventanos.new(
			title,
			frame.redraw_handler,
			frame.touch_handler,
			frame.drop_handler,
			frame.drag_handler,
			frame.scroll_handler
		)
end

return vtk
