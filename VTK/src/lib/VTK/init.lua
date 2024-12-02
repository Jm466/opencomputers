local ventanos = require("ventanos")
local core = require("VTK/core")

local vtk = {}

---@class Frame: Panel
---@field background_color integer?
---@field new fun(f: Frame, o: table?): Frame
local Frame = core.new_panel({
	parent_background = 0x797979,
})

Frame.true_redraw = Frame.redraw_handler
function Frame:redraw_handler()
	_ENV.setBackground(self.background_color and self.background_color or self.parent_background)
	self.fill()

	self.width, self.height = _ENV.getViewport()

	self:true_redraw()
end

local function new_frame(o)
	return Frame:new(o)
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

	frame.set = function(...)
		_ENV.WINDOW_HANDLE:set(...)
	end
	frame.fill = function(...)
		_ENV.WINDOW_HANDLE:fill(...)
	end
	frame.copy = function(...)
		_ENV.WINDOW_HANDLE:copy(...)
	end

	_ENV.set = nil
	_ENV.fill = nil
	_ENV.copy = nil

	_ENV.Redraw = function()
		frame:redraw_handler()
	end
	_ENV.Touch = function(...)
		frame:touch_handler(...)
	end
	_ENV.Drop = function(...)
		frame:drop_handler(...)
	end
	_ENV.Drag = function(...)
		frame:drag_handler(...)
	end
	_ENV.Scroll = function(...)
		frame:scroll_handler(...)
	end

	return frame
end

--- Creates a new window and returns the frame of the window and the window. Can be called anytime
---@param title string Title of the window
---@return Frame
---@return WindowHandle
vtk.new_window = function(title)
	local frame = new_frame()

	local window = ventanos.new(title, function()
		frame:redraw_handler()
	end, function(...)
		frame:touch_handler(...)
	end, function(...)
		frame:drop_handler(...)
	end, function(...)
		frame:drag_handler(...)
	end, function(...)
		frame:scroll_handler(...)
	end)

	function frame.set(...)
		ventanos.set(window, ...)
	end

	function frame.fill(...)
		ventanos.fill(window, ...)
	end

	function frame.copy(...)
		ventanos.copy(window, ...)
	end

	return frame, window
end

return vtk
