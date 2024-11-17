local ventanos = require("ventanos")
local core = require("VTK_core")

local vtk = {}

---@class Frame: Panel
---@field background_color integer
---@field foreground_color integer
local function new_frame()
	local frame = core.new_panel()

	frame.background_color = 0x79797

	local true_redraw = frame.redraw
	frame.redraw = function()
		_ENV.setBackground(frame.background_color)
		_ENV.fill()

		true_redraw()
	end

	return frame
end

--- Creates a frame for the window. Cannot be called more than once and must be called outside of the main function
---@return Frame
vtk.init = function()
	if INIT_CALLED then
		error("init() cannot be called more than once")
	end

	INIT_CALLED = true

	for func in { "Redraw", "Touch", "Drop", "Drag", "Scroll" } do
		if _ENV.value then
			error("Function " .. func .. "() already defined by user")
		end
	end

	local frame = new_frame()

	Redraw = function()
		frame.redraw_handler()
	end
	Touch = function(x, y, button)
		frame.touch_handler(x, y, button)
	end
	Drop = function(x, y, button)
		frame.drop_handler(x, y, button)
	end
	Drag = function(x, y, button)
		frame.drag_handler(x, y, button)
	end
	Scroll = function(x, y, direction)
		frame.scroll_handler(x, y, direction)
	end

	return frame
end

--- Creates a new window and returns the frame of the window and the window. Can be called anytime
---@param title string Title of the window
---@return Frame
---@return WindowHandle
vtk.new_window = function(title)
	local frame = new_frame()

	return frame,
		ventanos.new(title, function()
			frame.redraw_handler()
		end, function(x, y, button)
			frame.touch_handler(x, y, button)
		end, function(x, y, button)
			frame.drop_handler(x, y, button)
		end, function(x, y, button)
			frame.drag_handler(x, y, button)
		end, function(x, y, direction)
			frame.scroll_handler(x, y, direction)
		end)
end

return vtk
