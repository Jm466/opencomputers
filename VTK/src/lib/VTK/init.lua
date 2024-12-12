local ventanos = require("ventanos")
local core = require("VTK/core")

local api_functions = { "set", "fill", "copy", "setBackground", "setForeground", "setPaletteColor" }
local vtk = {}

---@class Frame: Panel
---@field background_color integer?
---@field new fun(f: Frame, o: table?): Frame
local Frame = core.new_panel()

Frame.true_redraw = Frame.redraw_handler
function Frame:redraw_handler()
	_ENV.setBackground(self.background_color)
	self.fill()

	self.width, self.height = _ENV.getViewport()

	self:true_redraw()
end

local function new_frame()
	return Frame:new()
end

---@param frame Frame
function Frame:init(frame)
	frame.background_color = 0x797979
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

	for func in pairs(api_functions) do
		frame[func] = function(...)
			_ENV.WINDOW_HANDLE[func](_ENV.WINDOW_HANDLE, ...)
		end
		_ENV[func] = nil
	end

	_ENV.Redraw = function()
		frame:redraw_handler()
		_ENV.setBackground(frame.background_color)
	end
	_ENV.Touch = function(...)
		frame:touch_handler(...)
		_ENV.setBackground(frame.background_color)
	end
	_ENV.Drop = function(...)
		frame:drop_handler(...)
		_ENV.setBackground(frame.background_color)
	end
	_ENV.Drag = function(...)
		frame:drag_handler(...)
		_ENV.setBackground(frame.background_color)
	end
	_ENV.Scroll = function(...)
		frame:scroll_handler(...)
		_ENV.setBackground(frame.background_color)
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
		_ENV.setBackground(frame.background_color)
	end, function(...)
		frame:touch_handler(...)
		_ENV.setBackground(frame.background_color)
	end, function(...)
		frame:drop_handler(...)
		_ENV.setBackground(frame.background_color)
	end, function(...)
		frame:drag_handler(...)
		_ENV.setBackground(frame.background_color)
	end, function(...)
		frame:scroll_handler(...)
		_ENV.setBackground(frame.background_color)
	end)

	for func in pairs(api_functions) do
		frame[func] = function(...)
			ventanos[func](window, ...)
		end
	end

	return frame, window
end

return vtk
